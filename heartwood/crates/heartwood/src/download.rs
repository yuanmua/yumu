//! Concurrent downloads with retries, hash verification and atomic writes.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use serde::de::DeserializeOwned;
use sha1::{Digest, Sha1};
use tokio::io::AsyncWriteExt;
use tokio::sync::Semaphore;
use tokio::task::JoinSet;

use crate::error::{Error, Result, io};
use crate::platform;

const USER_AGENT: &str = concat!("yumu/", env!("CARGO_PKG_VERSION"));
const ATTEMPTS: u32 = 3;

/// Byte counters shared between a download batch and whoever displays progress.
#[derive(Default)]
pub struct Progress {
    done: AtomicU64,
    total: AtomicU64,
}

impl Progress {
    pub fn add_total(&self, bytes: u64) {
        self.total.fetch_add(bytes, Ordering::Relaxed);
    }

    pub fn done(&self) -> u64 {
        self.done.load(Ordering::Relaxed)
    }

    pub fn total(&self) -> u64 {
        self.total.load(Ordering::Relaxed)
    }

    fn add_done(&self, bytes: u64) {
        self.done.fetch_add(bytes, Ordering::Relaxed);
    }

    fn undo(&self, bytes: u64) {
        self.done.fetch_sub(bytes, Ordering::Relaxed);
    }
}

/// One file to fetch. A known `sha1` makes the download verifiable and resumable across runs.
#[derive(Debug, Clone)]
pub struct Download {
    pub url: String,
    pub path: PathBuf,
    pub sha1: Option<String>,
    pub size: Option<u64>,
    pub executable: bool,
}

#[derive(Clone)]
pub struct Downloader {
    client: reqwest::Client,
    limit: Arc<Semaphore>,
}

impl Downloader {
    pub fn new(concurrency: usize) -> Result<Self> {
        let client = reqwest::Client::builder()
            .user_agent(USER_AGENT)
            // HTTP/2 multiplexes all requests to one host over a single connection, which
            // throttles downloads and misbehaves behind some proxies. Parallel HTTP/1.1 is faster.
            .http1_only()
            .connect_timeout(Duration::from_secs(15))
            .read_timeout(Duration::from_secs(30))
            .build()
            .map_err(|source| Error::Http {
                url: String::new(),
                source,
            })?;
        Ok(Self {
            client,
            limit: Arc::new(Semaphore::new(concurrency)),
        })
    }

    pub async fn get_json<T: DeserializeOwned>(&self, url: &str) -> Result<T> {
        let body = self.get_text(url).await?;
        serde_json::from_str(&body).map_err(|source| Error::Json {
            from: url.to_owned(),
            source,
        })
    }

    pub async fn get_text(&self, url: &str) -> Result<String> {
        retry(|| async {
            let response = self.client.get(url).send().await.map_err(http(url))?;
            check_status(response, url)?.text().await.map_err(http(url))
        })
        .await
    }

    /// Reject a download URL whose host is not in `allowed`. Keeps us inside each platform's terms.
    pub fn check_host(url: &str, allowed: &[&str]) -> Result<()> {
        let host = reqwest::Url::parse(url)
            .ok()
            .and_then(|parsed| parsed.host_str().map(str::to_owned))
            .ok_or_else(|| Error::Malformed(format!("url {url}")))?;
        if allowed.contains(&host.as_str()) {
            Ok(())
        } else {
            Err(Error::HostNotAllowed {
                url: url.to_owned(),
            })
        }
    }

    /// Download one file unless an identical copy already exists.
    pub async fn fetch(&self, download: &Download, progress: &Progress) -> Result<()> {
        if is_complete(download).await? {
            progress.add_done(download.size.unwrap_or(0));
            return Ok(());
        }
        retry(|| self.fetch_once(download, progress)).await
    }

    async fn fetch_once(&self, download: &Download, progress: &Progress) -> Result<()> {
        let path = &download.path;
        if let Some(parent) = path.parent() {
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(io(parent))?;
        }
        let part = part_path(path);
        let url = &download.url;
        let response = self.client.get(url).send().await.map_err(http(url))?;
        let mut response = check_status(response, url)?;

        let file = tokio::fs::File::create(&part).await.map_err(io(&part))?;
        let mut writer = tokio::io::BufWriter::new(file);
        let mut hasher = Sha1::new();
        let mut written = 0;
        let result = async {
            while let Some(chunk) = response.chunk().await.map_err(http(url))? {
                writer.write_all(&chunk).await.map_err(io(&part))?;
                hasher.update(&chunk);
                let len = chunk.len() as u64;
                written += len;
                progress.add_done(len);
            }
            writer.flush().await.map_err(io(&part))
        }
        .await;
        drop(writer);
        if let Err(error) = result {
            progress.undo(written);
            return Err(error);
        }

        let actual = hex(&hasher.finalize());
        if let Some(expected) = &download.sha1
            && *expected != actual
        {
            progress.undo(written);
            tokio::fs::remove_file(&part).await.map_err(io(&part))?;
            return Err(Error::HashMismatch {
                path: path.clone(),
                expected: expected.clone(),
                actual,
            });
        }
        tokio::fs::rename(&part, path).await.map_err(io(path))?;
        if download.executable {
            platform::set_executable(path).map_err(io(path))?;
        }
        Ok(())
    }

    /// Download everything, stopping at the first failure.
    pub async fn fetch_all(
        &self,
        downloads: Vec<Download>,
        progress: &Arc<Progress>,
    ) -> Result<()> {
        let mut set = JoinSet::new();
        for download in downloads {
            let this = self.clone();
            let progress = Arc::clone(progress);
            set.spawn(async move {
                let _permit = this.limit.acquire().await.map_err(|_| Error::Cancelled)?;
                this.fetch(&download, &progress).await
            });
        }
        while let Some(result) = set.join_next().await {
            if let Err(error) = result? {
                set.abort_all();
                return Err(error);
            }
        }
        Ok(())
    }
}

async fn is_complete(download: &Download) -> Result<bool> {
    let Ok(metadata) = tokio::fs::metadata(&download.path).await else {
        return Ok(false);
    };
    if download.size.is_some_and(|size| size != metadata.len()) {
        return Ok(false);
    }
    match &download.sha1 {
        Some(expected) => Ok(sha1_of_file(&download.path).await? == *expected),
        None => Ok(true),
    }
}

pub async fn sha1_of_file(path: &Path) -> Result<String> {
    let path = path.to_path_buf();
    tokio::task::spawn_blocking(move || {
        let mut file = std::fs::File::open(&path).map_err(io(&path))?;
        let mut hasher = Sha1::new();
        std::io::copy(&mut file, &mut hasher).map_err(io(&path))?;
        Ok(hex(&hasher.finalize()))
    })
    .await?
}

pub(crate) fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write;
    bytes
        .iter()
        .fold(String::with_capacity(bytes.len() * 2), |mut out, byte| {
            let _ = write!(out, "{byte:02x}");
            out
        })
}

fn part_path(path: &Path) -> PathBuf {
    let mut name = path.as_os_str().to_owned();
    name.push(".part");
    PathBuf::from(name)
}

fn check_status(response: reqwest::Response, url: &str) -> Result<reqwest::Response> {
    let status = response.status();
    if status.is_success() {
        Ok(response)
    } else {
        Err(Error::HttpStatus {
            url: url.to_owned(),
            status: status.as_u16(),
        })
    }
}

fn http(url: &str) -> impl FnOnce(reqwest::Error) -> Error + '_ {
    move |source| Error::Http {
        url: url.to_owned(),
        source,
    }
}

async fn retry<T, F, Fut>(mut operation: F) -> Result<T>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T>>,
{
    let mut attempt = 1;
    loop {
        match operation().await {
            Ok(value) => return Ok(value),
            Err(error) if attempt < ATTEMPTS && is_transient(&error) => {
                tracing::warn!(%error, attempt, "retrying");
                tokio::time::sleep(Duration::from_millis(500 << attempt)).await;
                attempt += 1;
            }
            Err(error) => return Err(error),
        }
    }
}

fn is_transient(error: &Error) -> bool {
    match error {
        Error::Http { .. } | Error::HashMismatch { .. } | Error::Io { .. } => true,
        Error::HttpStatus { status, .. } => *status >= 500,
        _ => false,
    }
}

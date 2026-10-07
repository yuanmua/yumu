//! Java runtimes: Mojang's official builds, installed under `cache/java/<component>`.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::download::{Download, Downloader, Progress};
use crate::error::{Error, Result, io};
use crate::mojang::{JAVA_RUNTIME_MANIFEST_URL, JavaFile, JavaFiles, JavaRuntimeManifest};
use crate::platform;

/// Make sure the runtime `component` (for example `java-runtime-delta`) is installed and return its `java` executable.
pub async fn ensure_runtime(
    downloader: &Downloader,
    cache_dir: &Path,
    component: &str,
    progress: &Arc<Progress>,
) -> Result<PathBuf> {
    let runtime_dir = cache_dir.join("java").join(component);
    let marker = runtime_dir.join(".complete");
    let executable = platform::java_executable(&runtime_dir);
    if exists(&marker).await && exists(&executable).await {
        return Ok(executable);
    }

    let manifest: JavaRuntimeManifest = downloader.get_json(JAVA_RUNTIME_MANIFEST_URL).await?;
    let runtime = platform::JAVA_RUNTIME_PLATFORMS
        .iter()
        .find_map(|key| manifest.get(*key)?.get(component)?.first())
        .ok_or_else(|| Error::JavaUnavailable {
            component: component.to_owned(),
        })?;
    let files: JavaFiles = downloader.get_json(&runtime.manifest.url).await?;

    let mut downloads = Vec::new();
    let mut links = Vec::new();
    for (relative, file) in &files.files {
        if relative.split('/').any(|segment| segment == "..") {
            return Err(Error::PathTraversal(relative.clone()));
        }
        let path = runtime_dir.join(relative);
        match file {
            JavaFile::Directory => tokio::fs::create_dir_all(&path).await.map_err(io(&path))?,
            JavaFile::File {
                downloads: refs,
                executable,
            } => {
                progress.add_total(refs.raw.size);
                downloads.push(Download {
                    url: refs.raw.url.clone(),
                    path,
                    sha1: Some(refs.raw.sha1.clone()),
                    size: Some(refs.raw.size),
                    executable: *executable,
                });
            }
            JavaFile::Link { target } => links.push((path, target.clone())),
        }
    }
    downloader.fetch_all(downloads, progress).await?;
    for (link, target) in links {
        if tokio::fs::symlink_metadata(&link).await.is_err() {
            platform::symlink(&target, &link).map_err(io(&link))?;
        }
    }
    tokio::fs::write(&marker, &runtime.version.name)
        .await
        .map_err(io(&marker))?;
    tracing::info!(component, version = %runtime.version.name, "java runtime installed");
    Ok(executable)
}

async fn exists(path: &Path) -> bool {
    tokio::fs::try_exists(path).await.unwrap_or(false)
}

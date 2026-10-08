//! Modpack import. Modrinth's `.mrpack` format first; `CurseForge` and Prism formats later.

use std::collections::HashMap;
use std::io::Read;
use std::path::{Component, Path, PathBuf};
use std::sync::Arc;

use serde::{Deserialize, Serialize};

use crate::download::{Download, Downloader, Progress};
use crate::error::{Error, Result, io};
use crate::install::extract_prefix;
use crate::instance::Store;

/// The hosts Modrinth's format allows pack files to come from.
const MRPACK_HOSTS: &[&str] = &[
    "cdn.modrinth.com",
    "github.com",
    "raw.githubusercontent.com",
    "gitlab.com",
];

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct MrpackIndex {
    format_version: u32,
    name: String,
    version_id: String,
    #[serde(default)]
    files: Vec<MrpackFile>,
    dependencies: HashMap<String, String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct MrpackFile {
    path: String,
    hashes: HashMap<String, String>,
    #[serde(default)]
    env: Option<HashMap<String, String>>,
    downloads: Vec<String>,
    file_size: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Summary {
    pub name: String,
    pub version: String,
    pub game_version: String,
    pub loader_kind: String,
    pub loader_version: String,
    pub file_count: usize,
}

/// Read the manifest without installing anything, so the interface can show what it is about to do.
pub fn inspect(path: &Path) -> Result<Summary> {
    let (summary, _) = read_index(path)?;
    Ok(summary)
}

/// Download a modpack from Modrinth into the cache and import it.
pub async fn import_from_modrinth(
    store: &Store,
    downloader: &Downloader,
    project_id: &str,
    progress: &Arc<Progress>,
) -> Result<String> {
    let dir = store.cache_dir().join("downloads");
    tokio::fs::create_dir_all(&dir).await.map_err(io(&dir))?;
    let file_name = crate::mods::install_file(downloader, &dir, project_id, None, progress).await?;
    import(store, downloader, &dir.join(file_name), None, progress).await
}

/// Create an instance from a `.mrpack`. On failure the half-made instance is removed again.
pub async fn import(
    store: &Store,
    downloader: &Downloader,
    path: &Path,
    name: Option<&str>,
    progress: &Arc<Progress>,
) -> Result<String> {
    let archive = path.to_path_buf();
    let (summary, index) = tokio::task::spawn_blocking(move || read_index(&archive)).await??;
    let id = store
        .create(name.unwrap_or(&summary.name), &summary.game_version)
        .await?;
    match fill(store, downloader, &id, &summary, &index, path, progress).await {
        Ok(()) => Ok(id),
        Err(error) => {
            if let Err(cleanup) = store.delete(&id).await {
                tracing::warn!(%cleanup, "could not remove failed import");
            }
            Err(error)
        }
    }
}

async fn fill(
    store: &Store,
    downloader: &Downloader,
    id: &str,
    summary: &Summary,
    index: &MrpackIndex,
    archive: &Path,
    progress: &Arc<Progress>,
) -> Result<()> {
    let mut instance = store.load(id).await?;
    instance.loader.kind = summary.loader_kind.clone();
    instance.loader.version = summary.loader_version.clone();
    store.save(id, &instance).await?;

    let game_dir = store.game_dir(id);
    let mut downloads = Vec::new();
    for file in &index.files {
        if file
            .env
            .as_ref()
            .and_then(|env| env.get("client"))
            .map(String::as_str)
            == Some("unsupported")
        {
            continue;
        }
        let url = file
            .downloads
            .first()
            .ok_or_else(|| Error::Malformed(format!("{} has no download", file.path)))?;
        Downloader::check_host(url, MRPACK_HOSTS)?;
        let sha1 = file
            .hashes
            .get("sha1")
            .ok_or_else(|| Error::Malformed(format!("{} has no sha1", file.path)))?;
        progress.add_total(file.file_size);
        downloads.push(Download {
            url: url.clone(),
            path: game_dir.join(safe_relative(&file.path)?),
            sha1: Some(sha1.clone()),
            size: Some(file.file_size),
            executable: false,
        });
    }
    downloader.fetch_all(downloads, progress).await?;

    let archive = archive.to_path_buf();
    tokio::task::spawn_blocking(move || {
        extract_prefix(&archive, &game_dir, "overrides/", &[])?;
        extract_prefix(&archive, &game_dir, "client-overrides/", &[])
    })
    .await?
}

fn read_index(path: &Path) -> Result<(Summary, MrpackIndex)> {
    let file = std::fs::File::open(path).map_err(io(path))?;
    let mut zip = zip::ZipArchive::new(file)?;
    let mut text = String::new();
    zip.by_name("modrinth.index.json")?
        .read_to_string(&mut text)
        .map_err(io(path))?;
    let index: MrpackIndex = serde_json::from_str(&text).map_err(|source| Error::Json {
        from: path.display().to_string(),
        source,
    })?;
    if index.format_version != 1 {
        return Err(Error::Unsupported("this modpack format version"));
    }
    let game_version = index
        .dependencies
        .get("minecraft")
        .cloned()
        .ok_or_else(|| Error::Malformed("modpack without minecraft version".to_owned()))?;
    let (loader_kind, loader_version) = ["fabric-loader", "quilt-loader", "forge", "neoforge"]
        .iter()
        .find_map(|key| {
            index
                .dependencies
                .get(*key)
                .map(|version| (key.trim_end_matches("-loader").to_owned(), version.clone()))
        })
        .unwrap_or_else(|| ("vanilla".to_owned(), String::new()));
    let summary = Summary {
        name: index.name.clone(),
        version: index.version_id.clone(),
        game_version,
        loader_kind,
        loader_version,
        file_count: index.files.len(),
    };
    Ok((summary, index))
}

/// A pack-relative path that cannot leave the game directory.
fn safe_relative(path: &str) -> Result<PathBuf> {
    let relative = Path::new(path);
    if relative
        .components()
        .any(|component| !matches!(component, Component::Normal(_)))
    {
        return Err(Error::PathTraversal(path.to_owned()));
    }
    Ok(relative.to_path_buf())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_escaping_paths() {
        assert!(safe_relative("mods/a.jar").is_ok());
        assert!(safe_relative("../a.jar").is_err());
        assert!(safe_relative("/etc/passwd").is_err());
        assert!(safe_relative("mods/../../a.jar").is_err());
    }
}

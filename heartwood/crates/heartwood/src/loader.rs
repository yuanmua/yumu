//! Mod loaders. Fabric and Quilt publish a version JSON profile directly; Forge and `NeoForge`
//! ship an installer that `forge.rs` unpacks and runs.

use std::path::{Path, PathBuf};

use serde::Deserialize;

use crate::download::Downloader;
use crate::error::{Error, Result, io};
use crate::forge;
use crate::mojang::VersionJson;

pub const VANILLA: &str = "vanilla";

struct Meta {
    kind: &'static str,
    versions: &'static str,
    profile: &'static str,
}

const LOADERS: &[Meta] = &[
    Meta {
        kind: "fabric",
        versions: "https://meta.fabricmc.net/v2/versions/loader/{game}",
        profile: "https://meta.fabricmc.net/v2/versions/loader/{game}/{loader}/profile/json",
    },
    Meta {
        kind: "quilt",
        versions: "https://meta.quiltmc.org/v3/versions/loader/{game}",
        profile: "https://meta.quiltmc.org/v3/versions/loader/{game}/{loader}/profile/json",
    },
];

#[derive(Debug, Clone, Deserialize)]
pub struct LoaderVersion {
    pub version: String,
    #[serde(default)]
    pub stable: bool,
}

#[derive(Deserialize)]
struct Entry {
    loader: LoaderVersion,
}

fn meta(kind: &str) -> Result<&'static Meta> {
    LOADERS
        .iter()
        .find(|meta| meta.kind == kind)
        .ok_or(Error::Unsupported("this mod loader"))
}

pub fn is_supported(kind: &str) -> bool {
    kind == VANILLA || is_forge_like(kind) || LOADERS.iter().any(|meta| meta.kind == kind)
}

pub fn is_forge_like(kind: &str) -> bool {
    kind == forge::FORGE || kind == forge::NEOFORGE
}

/// Loader versions for a game version, newest first.
pub async fn list_versions(
    downloader: &Downloader,
    kind: &str,
    game_version: &str,
) -> Result<Vec<LoaderVersion>> {
    if is_forge_like(kind) {
        return forge::list_versions(downloader, kind, game_version).await;
    }
    let url = meta(kind)?.versions.replace("{game}", game_version);
    let entries: Vec<Entry> = downloader.get_json(&url).await?;
    Ok(entries
        .into_iter()
        .map(|entry| LoaderVersion {
            // Quilt has no stable flag; treat anything that is not a pre-release as stable.
            stable: entry.loader.stable
                || !entry.loader.version.contains("beta") && !entry.loader.version.contains("pre"),
            version: entry.loader.version,
        })
        .collect())
}

/// Newest stable loader version, or the newest at all when none is marked stable.
pub async fn latest(downloader: &Downloader, kind: &str, game_version: &str) -> Result<String> {
    let versions = list_versions(downloader, kind, game_version).await?;
    versions
        .iter()
        .find(|version| version.stable)
        .or(versions.first())
        .map(|version| version.version.clone())
        .ok_or_else(|| Error::VersionNotFound(format!("{kind} for {game_version}")))
}

/// Version id of a loader profile, as the loader's own meta server names it.
pub fn profile_id(kind: &str, loader_version: &str, game_version: &str) -> String {
    if is_forge_like(kind) {
        return forge::profile_id(kind, loader_version, game_version);
    }
    format!("{kind}-loader-{loader_version}-{game_version}")
}

/// Make sure the loader's version JSON is in the cache and return its path.
pub async fn ensure_profile(
    downloader: &Downloader,
    cache_dir: &Path,
    kind: &str,
    loader_version: &str,
    game_version: &str,
) -> Result<PathBuf> {
    if is_forge_like(kind) {
        return forge::ensure_profile(downloader, cache_dir, kind, loader_version, game_version)
            .await;
    }
    let id = profile_id(kind, loader_version, game_version);
    let file = cache_dir
        .join("versions")
        .join(&id)
        .join(format!("{id}.json"));
    if tokio::fs::try_exists(&file).await.unwrap_or(false) {
        return Ok(file);
    }
    let url = meta(kind)?
        .profile
        .replace("{game}", game_version)
        .replace("{loader}", loader_version);
    let text = downloader.get_text(&url).await?;
    let profile: VersionJson =
        serde_json::from_str(&text).map_err(|source| Error::Json { from: url, source })?;
    if profile.inherits_from.as_deref() != Some(game_version) {
        return Err(Error::Malformed(format!(
            "loader profile {id} does not inherit {game_version}"
        )));
    }
    let dir = file.parent().unwrap_or(cache_dir);
    tokio::fs::create_dir_all(dir).await.map_err(io(dir))?;
    let part = dir.join(format!("{id}.json.part"));
    tokio::fs::write(&part, text).await.map_err(io(&part))?;
    tokio::fs::rename(&part, &file).await.map_err(io(&file))?;
    Ok(file)
}

//! Files the player drops into the game directory: shader packs and resource packs.
//! Mods share the same enable/disable convention (a `.disabled` suffix, as Prism and Modrinth App use).

use std::path::{Path, PathBuf};

use serde::Serialize;

use crate::error::{Error, Result, io};

pub const DISABLED_SUFFIX: &str = ".disabled";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    ShaderPacks,
    ResourcePacks,
}

impl Kind {
    pub fn parse(name: &str) -> Result<Self> {
        match name {
            "shaderpacks" => Ok(Self::ShaderPacks),
            "resourcepacks" => Ok(Self::ResourcePacks),
            other => Err(Error::InvalidRequest(format!(
                "unknown resource kind {other}"
            ))),
        }
    }

    pub fn dir_name(self) -> &'static str {
        match self {
            Self::ShaderPacks => "shaderpacks",
            Self::ResourcePacks => "resourcepacks",
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResourceFile {
    pub file_name: String,
    pub enabled: bool,
    pub size: u64,
}

pub async fn list(game_dir: &Path, kind: Kind) -> Result<Vec<ResourceFile>> {
    let mut files = Vec::new();
    for (file_name, size) in entries(&game_dir.join(kind.dir_name())).await? {
        let enabled = !file_name.ends_with(DISABLED_SUFFIX);
        files.push(ResourceFile {
            file_name: file_name.trim_end_matches(DISABLED_SUFFIX).to_owned(),
            enabled,
            size,
        });
    }
    files.sort_by(|a, b| a.file_name.cmp(&b.file_name));
    Ok(files)
}

/// Copy a file the user picked into the pack directory.
pub async fn add(game_dir: &Path, kind: Kind, source: &Path) -> Result<String> {
    let file_name = source
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| Error::InvalidFileName(source.display().to_string()))?;
    let dir = game_dir.join(kind.dir_name());
    tokio::fs::create_dir_all(&dir).await.map_err(io(&dir))?;
    let target = dir.join(file_name);
    tokio::fs::copy(source, &target)
        .await
        .map_err(io(&target))?;
    Ok(file_name.to_owned())
}

pub async fn remove(game_dir: &Path, kind: Kind, file_name: &str) -> Result<()> {
    remove_in(&game_dir.join(kind.dir_name()), file_name).await
}

pub async fn set_enabled(
    game_dir: &Path,
    kind: Kind,
    file_name: &str,
    enabled: bool,
) -> Result<()> {
    set_enabled_in(&game_dir.join(kind.dir_name()), file_name, enabled).await
}

/// `(name, size)` of every regular file in `dir`; a missing directory is simply empty.
pub(crate) async fn entries(dir: &Path) -> Result<Vec<(String, u64)>> {
    let mut entries = match tokio::fs::read_dir(dir).await {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(io(dir)(error)),
    };
    let mut files = Vec::new();
    while let Some(entry) = entries.next_entry().await.map_err(io(dir))? {
        let metadata = entry.metadata().await.map_err(io(&entry.path()))?;
        if let Some(name) = entry.file_name().to_str()
            && metadata.is_file()
            && !name.starts_with('.')
        {
            files.push((name.to_owned(), metadata.len()));
        }
    }
    Ok(files)
}

pub(crate) async fn remove_in(dir: &Path, file_name: &str) -> Result<()> {
    let path = existing(dir, file_name).await?;
    tokio::fs::remove_file(&path).await.map_err(io(&path))
}

pub(crate) async fn set_enabled_in(dir: &Path, file_name: &str, enabled: bool) -> Result<()> {
    let current = existing(dir, file_name).await?;
    let wanted = if enabled {
        dir.join(file_name)
    } else {
        dir.join(format!("{file_name}{DISABLED_SUFFIX}"))
    };
    if current != wanted {
        tokio::fs::rename(&current, &wanted)
            .await
            .map_err(io(&wanted))?;
    }
    Ok(())
}

/// The file as it exists now, enabled or disabled. `file_name` is always the enabled name.
async fn existing(dir: &Path, file_name: &str) -> Result<PathBuf> {
    validate_file_name(file_name)?;
    let enabled = dir.join(file_name);
    if tokio::fs::try_exists(&enabled).await.unwrap_or(false) {
        return Ok(enabled);
    }
    let disabled = dir.join(format!("{file_name}{DISABLED_SUFFIX}"));
    if tokio::fs::try_exists(&disabled).await.unwrap_or(false) {
        return Ok(disabled);
    }
    Err(Error::Io {
        path: enabled,
        source: std::io::Error::from(std::io::ErrorKind::NotFound),
    })
}

pub(crate) fn validate_file_name(file_name: &str) -> Result<()> {
    if file_name.is_empty()
        || file_name.contains(['/', '\\'])
        || file_name == "."
        || file_name == ".."
        || file_name.ends_with(DISABLED_SUFFIX)
    {
        return Err(Error::InvalidFileName(file_name.to_owned()));
    }
    Ok(())
}

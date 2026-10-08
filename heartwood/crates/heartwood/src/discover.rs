//! What is already on this computer: worlds and versions from other launchers, and installed Java runtimes.

use std::path::{Path, PathBuf};

use serde::Serialize;

use crate::error::{Error, Result, io};
use crate::instance::Store;
use crate::platform;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Scan {
    pub installations: Vec<Installation>,
    pub java: Vec<JavaInstall>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Installation {
    pub launcher: String,
    pub path: PathBuf,
    pub versions: Vec<String>,
    pub saves: Vec<Save>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Save {
    pub name: String,
    pub path: PathBuf,
    pub last_played: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JavaInstall {
    pub path: PathBuf,
    pub version: String,
    pub major: u32,
}

pub async fn scan() -> Result<Scan> {
    let mut installations = Vec::new();
    if let Ok(dir) = platform::official_launcher_dir()
        && dir.is_dir()
    {
        installations.push(Installation {
            launcher: "official".to_owned(),
            versions: version_ids(&dir.join("versions")).await,
            saves: saves_in(&dir.join("saves")).await,
            path: dir,
        });
    }
    for (launcher, dir) in platform::other_launcher_dirs() {
        let mut saves = Vec::new();
        for game_dir in game_dirs(&dir).await {
            saves.extend(saves_in(&game_dir.join("saves")).await);
        }
        if !saves.is_empty() {
            installations.push(Installation {
                launcher,
                path: dir,
                versions: Vec::new(),
                saves,
            });
        }
    }
    Ok(Scan {
        installations,
        java: java_installs().await,
    })
}

/// Copy a world folder into an instance. Refuses to overwrite an existing world of the same name.
pub async fn import_save(store: &Store, instance_id: &str, save: &Path) -> Result<String> {
    let name = save
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| Error::InvalidFileName(save.display().to_string()))?
        .to_owned();
    if !save.join("level.dat").is_file() {
        return Err(Error::Malformed(format!(
            "{} is not a world",
            save.display()
        )));
    }
    let target = store.game_dir(instance_id).join("saves").join(&name);
    if tokio::fs::try_exists(&target).await.unwrap_or(false) {
        return Err(Error::InstanceExists(name));
    }
    let source = save.to_path_buf();
    tokio::task::spawn_blocking(move || copy_dir(&source, &target)).await??;
    Ok(name)
}

fn copy_dir(source: &Path, target: &Path) -> Result<()> {
    std::fs::create_dir_all(target).map_err(io(target))?;
    for entry in std::fs::read_dir(source).map_err(io(source))? {
        let entry = entry.map_err(io(source))?;
        let destination = target.join(entry.file_name());
        let kind = entry.file_type().map_err(io(&entry.path()))?;
        if kind.is_dir() {
            copy_dir(&entry.path(), &destination)?;
        } else if kind.is_file() {
            std::fs::copy(entry.path(), &destination).map_err(io(&destination))?;
        }
    }
    Ok(())
}

async fn subdirs(dir: &Path) -> Vec<PathBuf> {
    let Ok(mut entries) = tokio::fs::read_dir(dir).await else {
        return Vec::new();
    };
    let mut dirs = Vec::new();
    while let Ok(Some(entry)) = entries.next_entry().await {
        if entry.file_type().await.is_ok_and(|kind| kind.is_dir()) {
            dirs.push(entry.path());
        }
    }
    dirs.sort();
    dirs
}

async fn version_ids(dir: &Path) -> Vec<String> {
    let mut ids = Vec::new();
    for version_dir in subdirs(dir).await {
        if let Some(id) = version_dir.file_name().and_then(|n| n.to_str())
            && version_dir.join(format!("{id}.json")).is_file()
        {
            ids.push(id.to_owned());
        }
    }
    ids
}

async fn saves_in(dir: &Path) -> Vec<Save> {
    let mut saves = Vec::new();
    for world in subdirs(dir).await {
        let level = world.join("level.dat");
        let Ok(metadata) = tokio::fs::metadata(&level).await else {
            continue;
        };
        let last_played = metadata
            .modified()
            .ok()
            .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
            .map_or(0, |elapsed| elapsed.as_secs());
        saves.push(Save {
            name: world
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default(),
            path: world,
            last_played,
        });
    }
    saves.sort_by_key(|save| std::cmp::Reverse(save.last_played));
    saves
}

/// Game directories of a Prism/MultiMC style launcher (`instances/<name>/.minecraft`) or a flat profile layout.
async fn game_dirs(launcher_dir: &Path) -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    for base in [
        launcher_dir.join("instances"),
        launcher_dir.join("profiles"),
    ] {
        for instance in subdirs(&base).await {
            for candidate in [
                instance.join(".minecraft"),
                instance.join("minecraft"),
                instance.clone(),
            ] {
                if candidate.join("saves").is_dir() {
                    dirs.push(candidate);
                    break;
                }
            }
        }
    }
    dirs
}

async fn java_installs() -> Vec<JavaInstall> {
    let mut found = Vec::new();
    for home in platform::java_homes().await {
        let path = home.join("bin").join(platform::JAVA_BINARY);
        let Ok(output) = tokio::process::Command::new(&path)
            .arg("-version")
            .output()
            .await
        else {
            continue;
        };
        let text = String::from_utf8_lossy(&output.stderr);
        let Some(version) = text.split('"').nth(1) else {
            continue;
        };
        let major = version
            .strip_prefix("1.")
            .unwrap_or(version)
            .split('.')
            .next()
            .and_then(|m| m.parse().ok())
            .unwrap_or(0);
        found.push(JavaInstall {
            path,
            version: version.to_owned(),
            major,
        });
    }
    found.sort_by_key(|java| std::cmp::Reverse(java.major));
    found
}

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
    pub versions: Vec<FoundVersion>,
    pub saves: Vec<Save>,
}

/// A version another launcher installed, reduced to what `instance.create` needs.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FoundVersion {
    pub id: String,
    pub game_version: String,
    pub loader_kind: String,
    pub loader_version: String,
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
            versions: versions_in(&dir.join("versions")).await,
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

async fn versions_in(dir: &Path) -> Vec<FoundVersion> {
    let mut versions = Vec::new();
    for version_dir in subdirs(dir).await {
        let Some(id) = version_dir.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        let Ok(text) = tokio::fs::read_to_string(version_dir.join(format!("{id}.json"))).await
        else {
            continue;
        };
        let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) else {
            continue;
        };
        versions.push(describe_version(id, &json));
    }
    versions
}

/// Game version from `inheritsFrom`, loader from the libraries or the FML arguments.
fn describe_version(id: &str, json: &serde_json::Value) -> FoundVersion {
    let game_version = json["inheritsFrom"].as_str().unwrap_or(id).to_owned();
    let libraries: Vec<&str> = json["libraries"]
        .as_array()
        .map(|libs| libs.iter().filter_map(|l| l["name"].as_str()).collect())
        .unwrap_or_default();
    let arguments: Vec<&str> = json["arguments"]["game"]
        .as_array()
        .map(|args| args.iter().filter_map(serde_json::Value::as_str).collect())
        .unwrap_or_default();
    let after = |flag: &str| {
        arguments
            .iter()
            .position(|a| *a == flag)
            .and_then(|i| arguments.get(i + 1))
            .map(|v| (*v).to_owned())
    };
    let library_version = |prefix: &str| {
        libraries
            .iter()
            .find_map(|name| name.strip_prefix(prefix))
            .map(|rest| rest.split(':').next().unwrap_or(rest).to_owned())
    };
    let (loader_kind, loader_version) = if let Some(v) = after("--fml.neoForgeVersion") {
        ("neoforge", v)
    } else if let Some(v) = after("--fml.forgeVersion") {
        ("forge", v)
    } else if let Some(v) = library_version("net.fabricmc:fabric-loader:") {
        ("fabric", v)
    } else if let Some(v) = library_version("org.quiltmc:quilt-loader:") {
        ("quilt", v)
    } else if let Some(v) = library_version("net.minecraftforge:forge:") {
        (
            "forge",
            v.split_once('-')
                .map_or(v.clone(), |(_, loader)| loader.to_owned()),
        )
    } else {
        ("vanilla", String::new())
    };
    FoundVersion {
        id: id.to_owned(),
        game_version,
        loader_kind: loader_kind.to_owned(),
        loader_version,
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn detects_loaders_from_other_launchers() {
        let neo = json!({"inheritsFrom": "1.21.1", "arguments": {"game": ["--fml.neoForgeVersion", "21.1.209"]}});
        let found = describe_version("1.21.1-NeoForge", &neo);
        assert_eq!(
            (
                found.game_version.as_str(),
                found.loader_kind.as_str(),
                found.loader_version.as_str()
            ),
            ("1.21.1", "neoforge", "21.1.209")
        );
        let fabric = json!({"inheritsFrom": "26.2", "libraries": [{"name": "net.fabricmc:fabric-loader:0.19.5"}]});
        assert_eq!(
            describe_version("26.2-Fabric", &fabric).loader_version,
            "0.19.5"
        );
        let legacy = json!({"inheritsFrom": "1.12.2", "libraries": [{"name": "net.minecraftforge:forge:1.12.2-14.23.5.2864"}]});
        assert_eq!(
            describe_version("1.12.2-Forge", &legacy).loader_version,
            "14.23.5.2864"
        );
        assert_eq!(
            describe_version("1.21.1", &json!({})).loader_kind,
            "vanilla"
        );
    }
}

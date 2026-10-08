//! Forge and `NeoForge` (Minecraft 1.13+): download the installer jar, lift `version.json` and
//! `install_profile.json` out of it, then run the client-side processors with the instance's Java.

use std::collections::HashMap;
use std::io::Read;
use std::path::{Path, PathBuf};

use serde::Deserialize;

use crate::download::{Download, Downloader, Progress};
use crate::error::{Error, Result, io};
use crate::install::{extract_prefix, read_json};
use crate::loader::LoaderVersion;
use crate::mojang::{Library, maven_path};
use crate::platform;

pub const FORGE: &str = "forge";
pub const NEOFORGE: &str = "neoforge";
const FORGE_MAVEN: &str = "https://maven.minecraftforge.net/net/minecraftforge/forge";
const FORGE_PROMOTIONS: &str =
    "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json";
const NEOFORGE_MAVEN: &str = "https://maven.neoforged.net/releases/net/neoforged/neoforge";
const NEOFORGE_VERSIONS: &str =
    "https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge";
const PROFILE_FILE: &str = "install_profile.json";
const INSTALLER_FILE: &str = "installer.jar";
const PROCESSED_MARKER: &str = ".processed";

#[derive(Debug, Deserialize)]
pub struct InstallProfile {
    #[serde(default)]
    pub spec: Option<u32>,
    #[serde(default)]
    pub data: HashMap<String, SideValues>,
    #[serde(default)]
    pub processors: Vec<Processor>,
    #[serde(default)]
    pub libraries: Vec<Library>,
}

#[derive(Debug, Deserialize)]
pub struct SideValues {
    pub client: String,
}

#[derive(Debug, Deserialize)]
pub struct Processor {
    pub jar: String,
    #[serde(default)]
    pub classpath: Vec<String>,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub sides: Option<Vec<String>>,
}

pub async fn list_versions(
    downloader: &Downloader,
    kind: &str,
    game_version: &str,
) -> Result<Vec<LoaderVersion>> {
    if kind == NEOFORGE {
        #[derive(Deserialize)]
        struct Versions {
            versions: Vec<String>,
        }
        let prefix = neoforge_prefix(game_version);
        let all: Versions = downloader.get_json(NEOFORGE_VERSIONS).await?;
        return Ok(all
            .versions
            .into_iter()
            .rev()
            .filter(|version| version.starts_with(&prefix))
            .map(|version| LoaderVersion {
                stable: !version.contains("beta"),
                version,
            })
            .collect());
    }
    let xml = downloader
        .get_text(&format!("{FORGE_MAVEN}/maven-metadata.xml"))
        .await?;
    let prefix = format!("{game_version}-");
    let versions: Vec<String> = xml
        .split("<version>")
        .skip(1)
        .filter_map(|rest| rest.split_once("</version>").map(|(version, _)| version))
        .filter_map(|version| version.strip_prefix(&prefix))
        .map(str::to_owned)
        .collect();
    let promotions: serde_json::Value = downloader
        .get_json(FORGE_PROMOTIONS)
        .await
        .unwrap_or_default();
    let recommended = promotions["promos"][format!("{game_version}-recommended")].as_str();
    Ok(versions
        .into_iter()
        .rev()
        .map(|version| LoaderVersion {
            stable: recommended.is_some_and(|r| r == version),
            version,
        })
        .collect())
}

/// `NeoForge` numbers versions after the game: 1.21.1 → 21.1.x, 26.3 → 26.3.x.
fn neoforge_prefix(game_version: &str) -> String {
    let rest = game_version.strip_prefix("1.").unwrap_or(game_version);
    if rest.contains('.') {
        format!("{rest}.")
    } else {
        format!("{rest}.0.")
    }
}

pub fn profile_id(kind: &str, loader_version: &str, game_version: &str) -> String {
    if kind == NEOFORGE {
        format!("neoforge-{loader_version}")
    } else {
        format!("{game_version}-forge-{loader_version}")
    }
}

fn installer_url(kind: &str, loader_version: &str, game_version: &str) -> String {
    if kind == NEOFORGE {
        format!("{NEOFORGE_MAVEN}/{loader_version}/neoforge-{loader_version}-installer.jar")
    } else {
        format!(
            "{FORGE_MAVEN}/{game_version}-{loader_version}/forge-{game_version}-{loader_version}-installer.jar"
        )
    }
}

/// Download the installer and unpack the profile JSON files and bundled Maven artifacts. Returns the version JSON path.
pub async fn ensure_profile(
    downloader: &Downloader,
    cache_dir: &Path,
    kind: &str,
    loader_version: &str,
    game_version: &str,
) -> Result<PathBuf> {
    let id = profile_id(kind, loader_version, game_version);
    let dir = cache_dir.join("versions").join(&id);
    let version_file = dir.join(format!("{id}.json"));
    if tokio::fs::try_exists(&version_file).await.unwrap_or(false) {
        return Ok(version_file);
    }
    let installer = dir.join(INSTALLER_FILE);
    let request = Download {
        url: installer_url(kind, loader_version, game_version),
        path: installer.clone(),
        sha1: None,
        size: None,
        executable: false,
    };
    downloader.fetch(&request, &Progress::default()).await?;
    let libraries_dir = cache_dir.join("libraries");
    let target = version_file.clone();
    tokio::task::spawn_blocking(move || unpack(&installer, &dir, &target, &libraries_dir))
        .await??;
    Ok(version_file)
}

fn unpack(installer: &Path, dir: &Path, version_file: &Path, libraries_dir: &Path) -> Result<()> {
    let file = std::fs::File::open(installer).map_err(io(installer))?;
    let mut zip = zip::ZipArchive::new(file)?;
    let mut read = |name: &str| -> Result<String> {
        let mut text = String::new();
        zip.by_name(name)
            .map_err(|_| Error::Unsupported("Forge for Minecraft 1.12 and older"))?
            .read_to_string(&mut text)
            .map_err(io(installer))?;
        Ok(text)
    };
    let profile_text = read(PROFILE_FILE)?;
    let version_text = read("version.json")?;
    let profile: serde_json::Value =
        serde_json::from_str(&profile_text).map_err(|source| Error::Json {
            from: installer.display().to_string(),
            source,
        })?;
    if profile.get("processors").is_none() {
        return Err(Error::Unsupported("Forge for Minecraft 1.12 and older"));
    }
    extract_prefix(installer, libraries_dir, "maven/", &[])?;
    std::fs::write(dir.join(PROFILE_FILE), profile_text).map_err(io(dir))?;
    std::fs::write(version_file, version_text).map_err(io(version_file))
}

pub async fn load_profile(version_file: &Path) -> Result<InstallProfile> {
    let dir = version_file.parent().unwrap_or(version_file);
    read_json(&dir.join(PROFILE_FILE)).await
}

/// Run the client processors once; later launches find the marker and skip straight to the game.
pub async fn process(
    version_file: &Path,
    profile: &InstallProfile,
    java: &Path,
    libraries_dir: &Path,
    vanilla_jar: &Path,
    game_version: &str,
) -> Result<()> {
    let dir = version_file.parent().unwrap_or(version_file).to_path_buf();
    let marker = dir.join(PROCESSED_MARKER);
    if tokio::fs::try_exists(&marker).await.unwrap_or(false) {
        return Ok(());
    }
    let work = dir.join("work");
    tokio::fs::create_dir_all(&work).await.map_err(io(&work))?;
    let installer = dir.join(INSTALLER_FILE);
    let mut context = Context {
        profile,
        libraries_dir,
        installer: &installer,
        work: &work,
        builtins: HashMap::from([
            ("MINECRAFT_JAR", vanilla_jar.display().to_string()),
            ("SIDE", "client".to_owned()),
            ("INSTALLER", installer.display().to_string()),
            ("ROOT", work.display().to_string()),
            ("MINECRAFT_VERSION", game_version.to_owned()),
            ("LIBRARY_DIR", libraries_dir.display().to_string()),
        ]),
    };

    for processor in &profile.processors {
        if processor
            .sides
            .as_ref()
            .is_some_and(|sides| !sides.iter().any(|s| s == "client"))
        {
            continue;
        }
        let jar = libraries_dir.join(artifact_path(&processor.jar)?);
        let main_class = tokio::task::spawn_blocking({
            let jar = jar.clone();
            move || main_class(&jar)
        })
        .await??;
        let mut classpath = vec![jar.display().to_string()];
        for entry in &processor.classpath {
            classpath.push(
                libraries_dir
                    .join(artifact_path(entry)?)
                    .display()
                    .to_string(),
            );
        }
        let mut args = Vec::with_capacity(processor.args.len());
        for arg in &processor.args {
            args.push(context.resolve(arg)?);
        }
        tracing::info!(jar = %processor.jar, "running loader processor");
        let output = tokio::process::Command::new(java)
            .arg("-cp")
            .arg(classpath.join(platform::CLASSPATH_SEPARATOR))
            .arg(&main_class)
            .args(&args)
            .current_dir(&work)
            .output()
            .await
            .map_err(Error::Spawn)?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let stdout = String::from_utf8_lossy(&output.stdout);
            let tail: String = format!("{stdout}\n{stderr}")
                .chars()
                .rev()
                .take(2000)
                .collect::<Vec<_>>()
                .into_iter()
                .rev()
                .collect();
            return Err(Error::LoaderInstallFailed {
                step: processor.jar.clone(),
                detail: tail,
            });
        }
    }
    tokio::fs::remove_dir_all(&work).await.map_err(io(&work))?;
    tokio::fs::write(&marker, b"").await.map_err(io(&marker))
}

struct Context<'a> {
    profile: &'a InstallProfile,
    libraries_dir: &'a Path,
    installer: &'a Path,
    work: &'a Path,
    builtins: HashMap<&'static str, String>,
}

impl Context<'_> {
    /// Expand `{KEY}` placeholders, then turn `[group:artifact:version]` into a library path.
    fn resolve(&mut self, arg: &str) -> Result<String> {
        let mut result = arg.to_owned();
        while let Some(start) = result.find('{') {
            let Some(end) = result[start..].find('}') else {
                break;
            };
            let key = result[start + 1..start + end].to_owned();
            let value = self.value(&key)?;
            result.replace_range(start..=start + end, &value);
        }
        if result.starts_with('[') && result.ends_with(']') {
            return Ok(self
                .libraries_dir
                .join(artifact_path(&result)?)
                .display()
                .to_string());
        }
        Ok(result)
    }

    fn value(&mut self, key: &str) -> Result<String> {
        if let Some(builtin) = self.builtins.get(key) {
            return Ok(builtin.clone());
        }
        let raw = &self
            .profile
            .data
            .get(key)
            .ok_or_else(|| Error::Malformed(format!("install profile has no data entry {key}")))?
            .client;
        if raw.starts_with('[') && raw.ends_with(']') {
            return Ok(self
                .libraries_dir
                .join(artifact_path(raw)?)
                .display()
                .to_string());
        }
        if let Some(literal) = raw.strip_prefix('\'').and_then(|r| r.strip_suffix('\'')) {
            return Ok(literal.to_owned());
        }
        if let Some(inside) = raw.strip_prefix('/') {
            let target = self.work.join(inside.replace('/', "_"));
            if !target.exists() {
                extract_one(self.installer, inside, &target)?;
            }
            return Ok(target.display().to_string());
        }
        Ok(raw.clone())
    }
}

/// `[net.minecraft:client:1.21.1:slim]` or a bare coordinate → relative library path.
fn artifact_path(coordinate: &str) -> Result<String> {
    let inner = coordinate.trim_start_matches('[').trim_end_matches(']');
    maven_path(inner).ok_or_else(|| Error::Malformed(format!("artifact coordinate {coordinate}")))
}

fn extract_one(installer: &Path, name: &str, target: &Path) -> Result<()> {
    let file = std::fs::File::open(installer).map_err(io(installer))?;
    let mut zip = zip::ZipArchive::new(file)?;
    let mut entry = zip.by_name(name)?;
    let mut output = std::fs::File::create(target).map_err(io(target))?;
    std::io::copy(&mut entry, &mut output).map_err(io(target))?;
    Ok(())
}

fn main_class(jar: &Path) -> Result<String> {
    let file = std::fs::File::open(jar).map_err(io(jar))?;
    let mut zip = zip::ZipArchive::new(file)?;
    let mut manifest = String::new();
    zip.by_name("META-INF/MANIFEST.MF")?
        .read_to_string(&mut manifest)
        .map_err(io(jar))?;
    manifest
        .lines()
        .find_map(|line| line.strip_prefix("Main-Class:"))
        .map(|name| name.trim().to_owned())
        .ok_or_else(|| Error::Malformed(format!("{} has no Main-Class", jar.display())))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn neoforge_prefixes() {
        assert_eq!(neoforge_prefix("1.21.1"), "21.1.");
        assert_eq!(neoforge_prefix("1.21"), "21.0.");
        assert_eq!(neoforge_prefix("26.3"), "26.3.");
    }

    #[test]
    fn profile_ids() {
        assert_eq!(
            profile_id(FORGE, "52.1.16", "1.21.1"),
            "1.21.1-forge-52.1.16"
        );
        assert_eq!(
            profile_id(NEOFORGE, "21.1.209", "1.21.1"),
            "neoforge-21.1.209"
        );
    }
}

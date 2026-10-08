//! Mods: the local `mods/` directory plus Modrinth for search, install and dependency resolution.

use std::collections::{HashMap, HashSet};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::download::{Download, Downloader, Progress, sha1_of_file};
use crate::error::{Error, Result, io};
use crate::resource::{DISABLED_SUFFIX, entries, remove_in, set_enabled_in};

const API: &str = "https://api.modrinth.com/v2";
/// Modrinth serves every file from its CDN; anything else in a version would be a bug or an attack.
const MODRINTH_HOSTS: &[&str] = &["cdn.modrinth.com"];

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all(serialize = "camelCase"))]
pub struct SearchHit {
    pub project_id: String,
    pub slug: String,
    pub title: String,
    pub description: String,
    #[serde(default)]
    pub icon_url: Option<String>,
    pub downloads: u64,
    pub author: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all(serialize = "camelCase"))]
pub struct SearchResult {
    pub hits: Vec<SearchHit>,
    pub total_hits: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Version {
    pub id: String,
    pub project_id: String,
    pub name: String,
    pub version_number: String,
    pub files: Vec<VersionFile>,
    #[serde(default)]
    pub dependencies: Vec<Dependency>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct VersionFile {
    pub url: String,
    pub filename: String,
    pub primary: bool,
    pub size: u64,
    pub hashes: Hashes,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Hashes {
    pub sha1: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Dependency {
    #[serde(default)]
    pub project_id: Option<String>,
    pub dependency_type: String,
}

#[derive(Debug, Clone, Deserialize)]
struct Project {
    id: String,
    title: String,
}

/// What we know about an installed jar, keyed by its sha1 in the shared index.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModRecord {
    pub project_id: String,
    pub version_id: String,
    pub title: String,
    pub version_number: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalMod {
    pub file_name: String,
    pub enabled: bool,
    pub size: u64,
    /// Name from the jar's own metadata, or the file stem.
    pub name: String,
    pub version: String,
    pub record: Option<ModRecord>,
}

/// Search Modrinth. `project_type` is `mod`, `modpack`, `resourcepack` or `shader`; the loader
/// facet only makes sense for mods and modpacks, the game version facet for everything but modpacks
/// when none is given.
pub async fn search(
    downloader: &Downloader,
    project_type: &str,
    query: &str,
    game_version: Option<&str>,
    loader: Option<&str>,
    offset: u32,
) -> Result<SearchResult> {
    let mut facets = vec![vec![format!("project_type:{project_type}")]];
    if let Some(game_version) = game_version {
        facets.push(vec![format!("versions:{game_version}")]);
    }
    if let Some(loader) = loader.filter(|_| project_type == "mod" || project_type == "modpack") {
        facets.push(vec![format!("categories:{loader}")]);
    }
    let facets = json!(facets).to_string();
    let url = reqwest::Url::parse_with_params(
        &format!("{API}/search"),
        [
            ("query", query),
            ("facets", facets.as_str()),
            ("limit", "20"),
            ("offset", &offset.to_string()),
            (
                "index",
                if query.is_empty() {
                    "downloads"
                } else {
                    "relevance"
                },
            ),
        ],
    )
    .map_err(|error| Error::Malformed(error.to_string()))?;
    downloader.get_json(url.as_str()).await
}

/// Versions of a project, newest first, optionally narrowed to a game version and loader.
pub async fn versions(
    downloader: &Downloader,
    project_id: &str,
    game_version: Option<&str>,
    loader: Option<&str>,
) -> Result<Vec<Version>> {
    let mut params = Vec::new();
    if let Some(loader) = loader {
        params.push(("loaders", json!([loader]).to_string()));
    }
    if let Some(game_version) = game_version {
        params.push(("game_versions", json!([game_version]).to_string()));
    }
    let url =
        reqwest::Url::parse_with_params(&format!("{API}/project/{project_id}/version"), params)
            .map_err(|error| Error::Malformed(error.to_string()))?;
    downloader.get_json(url.as_str()).await
}

/// The primary file of a version, checked against Modrinth's CDN and our file name rules.
pub fn primary_file(version: &Version) -> Result<&VersionFile> {
    let file = version
        .files
        .iter()
        .find(|file| file.primary)
        .or(version.files.first())
        .ok_or_else(|| Error::Malformed(format!("version {} has no files", version.id)))?;
    Downloader::check_host(&file.url, MODRINTH_HOSTS)?;
    crate::resource::validate_file_name(&file.filename)?;
    Ok(file)
}

/// Download the newest compatible version of a project into `dir` (shader packs, resource packs,
/// modpack archives). Returns the file name.
pub async fn install_file(
    downloader: &Downloader,
    dir: &Path,
    project_id: &str,
    game_version: Option<&str>,
    progress: &Arc<Progress>,
) -> Result<String> {
    let version = versions(downloader, project_id, game_version, None)
        .await?
        .into_iter()
        .next()
        .ok_or_else(|| Error::ModNotCompatible {
            project: project_id.to_owned(),
            game_version: game_version.unwrap_or("*").to_owned(),
            loader: "*".to_owned(),
        })?;
    let file = primary_file(&version)?;
    progress.add_total(file.size);
    let request = Download {
        url: file.url.clone(),
        path: dir.join(&file.filename),
        sha1: Some(file.hashes.sha1.clone()),
        size: Some(file.size),
        executable: false,
    };
    downloader.fetch(&request, progress).await?;
    Ok(file.filename.clone())
}

/// Install a project and its required dependencies. Returns what was added.
pub async fn install(
    downloader: &Downloader,
    game_dir: &Path,
    cache_dir: &Path,
    project_id: &str,
    game_version: &str,
    loader: &str,
    progress: &Arc<Progress>,
) -> Result<Vec<ModRecord>> {
    let mut index = Index::load(cache_dir).await?;
    let present: HashSet<String> = list(game_dir, cache_dir)
        .await?
        .into_iter()
        .filter_map(|m| m.record.map(|record| record.project_id))
        .collect();

    let mut planned: Vec<Version> = Vec::new();
    let mut queue = vec![project_id.to_owned()];
    while let Some(id) = queue.pop() {
        if present.contains(&id) || planned.iter().any(|version| version.project_id == id) {
            continue;
        }
        let version = versions(downloader, &id, Some(game_version), Some(loader))
            .await?
            .into_iter()
            .next()
            .ok_or_else(|| Error::ModNotCompatible {
                project: id.clone(),
                game_version: game_version.to_owned(),
                loader: loader.to_owned(),
            })?;
        queue.extend(
            version
                .dependencies
                .iter()
                .filter(|dependency| dependency.dependency_type == "required")
                .filter_map(|dependency| dependency.project_id.clone()),
        );
        planned.push(version);
    }

    let ids = json!(
        planned
            .iter()
            .map(|v| v.project_id.as_str())
            .collect::<Vec<_>>()
    )
    .to_string();
    let url = reqwest::Url::parse_with_params(&format!("{API}/projects"), [("ids", ids.as_str())])
        .map_err(|error| Error::Malformed(error.to_string()))?;
    let projects: Vec<Project> = downloader.get_json(url.as_str()).await?;
    let titles: HashMap<&str, &str> = projects
        .iter()
        .map(|p| (p.id.as_str(), p.title.as_str()))
        .collect();

    let mods_dir = game_dir.join("mods");
    let mut downloads = Vec::new();
    let mut installed = Vec::new();
    for version in &planned {
        let file = primary_file(version)?;
        progress.add_total(file.size);
        downloads.push(Download {
            url: file.url.clone(),
            path: mods_dir.join(&file.filename),
            sha1: Some(file.hashes.sha1.clone()),
            size: Some(file.size),
            executable: false,
        });
        let record = ModRecord {
            project_id: version.project_id.clone(),
            version_id: version.id.clone(),
            title: titles
                .get(version.project_id.as_str())
                .map_or_else(|| version.name.clone(), |title| (*title).to_owned()),
            version_number: version.version_number.clone(),
        };
        index
            .records
            .insert(file.hashes.sha1.clone(), record.clone());
        installed.push(record);
    }
    downloader.fetch_all(downloads, progress).await?;
    index.save(cache_dir).await?;
    Ok(installed)
}

pub async fn list(game_dir: &Path, cache_dir: &Path) -> Result<Vec<LocalMod>> {
    let index = Index::load(cache_dir).await?;
    let mods_dir = game_dir.join("mods");
    let mut mods = Vec::new();
    for (name, size) in entries(&mods_dir).await? {
        let enabled = !name.ends_with(DISABLED_SUFFIX);
        let file_name = name.trim_end_matches(DISABLED_SUFFIX).to_owned();
        if !Path::new(&file_name)
            .extension()
            .is_some_and(|extension| extension.eq_ignore_ascii_case("jar"))
        {
            continue;
        }
        let path = mods_dir.join(&name);
        let record = index.records.get(&sha1_of_file(&path).await?).cloned();
        let metadata = tokio::task::spawn_blocking(move || jar_metadata(&path)).await?;
        let (meta_name, version) = metadata.unwrap_or_default();
        mods.push(LocalMod {
            name: if meta_name.is_empty() {
                file_name.trim_end_matches(".jar").to_owned()
            } else {
                meta_name
            },
            file_name,
            enabled,
            size,
            version,
            record,
        });
    }
    mods.sort_by_key(|m| m.name.to_lowercase());
    Ok(mods)
}

pub async fn set_enabled(game_dir: &Path, file_name: &str, enabled: bool) -> Result<()> {
    set_enabled_in(&game_dir.join("mods"), file_name, enabled).await
}

pub async fn remove(game_dir: &Path, file_name: &str) -> Result<()> {
    remove_in(&game_dir.join("mods"), file_name).await
}

/// `(name, version)` from the loader metadata inside a mod jar, if any.
fn jar_metadata(path: &Path) -> Option<(String, String)> {
    let file = std::fs::File::open(path).ok()?;
    let mut zip = zip::ZipArchive::new(file).ok()?;
    let read = |zip: &mut zip::ZipArchive<std::fs::File>, name: &str| -> Option<String> {
        let mut text = String::new();
        zip.by_name(name).ok()?.read_to_string(&mut text).ok()?;
        Some(text)
    };
    if let Some(text) = read(&mut zip, "fabric.mod.json") {
        let value: serde_json::Value = serde_json::from_str(&text).ok()?;
        return Some((string(&value["name"]), string(&value["version"])));
    }
    if let Some(text) = read(&mut zip, "quilt.mod.json") {
        let value: serde_json::Value = serde_json::from_str(&text).ok()?;
        let loader = &value["quilt_loader"];
        return Some((
            string(&loader["metadata"]["name"]),
            string(&loader["version"]),
        ));
    }
    for name in ["META-INF/neoforge.mods.toml", "META-INF/mods.toml"] {
        if let Some(text) = read(&mut zip, name) {
            let value: toml::Value = toml::from_str(&text).ok()?;
            let first = value.get("mods")?.as_array()?.first()?;
            let field = |key: &str| {
                first
                    .get(key)
                    .and_then(toml::Value::as_str)
                    .unwrap_or_default()
                    .to_owned()
            };
            return Some((field("displayName"), field("version")));
        }
    }
    None
}

fn string(value: &serde_json::Value) -> String {
    value.as_str().unwrap_or_default().to_owned()
}

/// sha1 → Modrinth record for every jar Yumu installed. Lives in the cache: losing it only loses provenance.
#[derive(Default, Serialize, Deserialize)]
struct Index {
    records: HashMap<String, ModRecord>,
}

impl Index {
    fn path(cache_dir: &Path) -> PathBuf {
        cache_dir.join("meta").join("modrinth-index.json")
    }

    async fn load(cache_dir: &Path) -> Result<Self> {
        let path = Self::path(cache_dir);
        match tokio::fs::read_to_string(&path).await {
            Ok(text) => serde_json::from_str(&text).map_err(|source| Error::Json {
                from: path.display().to_string(),
                source,
            }),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
            Err(error) => Err(io(&path)(error)),
        }
    }

    async fn save(&self, cache_dir: &Path) -> Result<()> {
        let path = Self::path(cache_dir);
        let dir = path.parent().unwrap_or(cache_dir);
        tokio::fs::create_dir_all(dir).await.map_err(io(dir))?;
        let part = dir.join("modrinth-index.json.part");
        let text = serde_json::to_string(self).map_err(|source| Error::Json {
            from: path.display().to_string(),
            source,
        })?;
        tokio::fs::write(&part, text).await.map_err(io(&part))?;
        tokio::fs::rename(&part, &path).await.map_err(io(&path))
    }
}

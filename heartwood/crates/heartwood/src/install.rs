//! Bring an instance to a launchable state: version JSON, loader profile, Java, libraries, client jar, assets, natives.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::download::{Download, Downloader, Progress};
use crate::error::{Error, Result, io};
use crate::instance::{Instance, Store};
use crate::mojang::{
    ASSET_BASE_URL, AssetIndex, FileRef, Library, VersionJson, VersionManifest, maven_path,
};
use crate::mojang::{VERSION_MANIFEST_URL, fetch_manifest};
use crate::rules::{Features, allows};
use crate::{forge, java, loader, platform};

/// Everything `launch` needs, all present on disk.
pub struct Prepared {
    pub version: VersionJson,
    pub asset_index_id: String,
    pub java: PathBuf,
    pub classpath: Vec<PathBuf>,
    pub natives_dir: PathBuf,
    pub assets_dir: PathBuf,
    pub libraries_dir: PathBuf,
}

pub async fn install(
    store: &Store,
    downloader: &Downloader,
    id: &str,
    instance: &mut Instance,
    progress: &Arc<Progress>,
) -> Result<Prepared> {
    let cache = store.cache_dir();
    let game_version = instance.game.version.clone();
    let (version, installer) = resolve_version(store, downloader, id, instance, &cache).await?;
    let asset_index = version
        .asset_index
        .clone()
        .ok_or_else(|| Error::Malformed(format!("version {} has no asset index", version.id)))?;
    let client = version
        .downloads
        .as_ref()
        .map(|downloads| downloads.client.clone())
        .ok_or_else(|| {
            Error::Malformed(format!("version {} has no client download", version.id))
        })?;

    let component = version
        .java_version
        .as_ref()
        .map_or("jre-legacy", |java| java.component.as_str());
    let java = java::ensure_runtime(downloader, &cache, component, progress).await?;

    let libraries_dir = cache.join("libraries");
    let installer_libraries = installer
        .as_ref()
        .map(|(_, profile)| profile.libraries.as_slice())
        .unwrap_or_default();
    let Libraries {
        mut downloads,
        mut classpath,
        natives,
    } = collect_libraries(&version, installer_libraries, &libraries_dir, progress)?;

    let client_jar = cache
        .join("versions")
        .join(&game_version)
        .join(format!("{game_version}.jar"));
    downloads.push(download(&client, client_jar.clone(), progress));
    classpath.push(client_jar);

    let assets_dir = cache.join("assets");
    collect_assets(
        downloader,
        &assets_dir,
        &asset_index,
        &mut downloads,
        progress,
    )
    .await?;

    downloader.fetch_all(downloads, progress).await?;

    if let Some((version_file, profile)) = &installer {
        let vanilla_jar = cache
            .join("versions")
            .join(&game_version)
            .join(format!("{game_version}.jar"));
        forge::process(
            version_file,
            profile,
            &java,
            &libraries_dir,
            &vanilla_jar,
            &game_version,
        )
        .await?;
    }
    for path in &classpath {
        if !tokio::fs::try_exists(path).await.unwrap_or(false) {
            return Err(Error::Malformed(format!(
                "library {} is missing after install",
                path.display()
            )));
        }
    }

    let natives_dir = cache.join("natives").join(&version.id);
    tokio::fs::create_dir_all(&natives_dir)
        .await
        .map_err(io(&natives_dir))?;
    for (jar, exclude) in natives {
        let dest = natives_dir.clone();
        tokio::task::spawn_blocking(move || extract(&jar, &dest, &exclude)).await??;
    }

    Ok(Prepared {
        version,
        asset_index_id: asset_index.id,
        java,
        classpath,
        natives_dir,
        assets_dir,
        libraries_dir,
    })
}

struct Libraries {
    downloads: Vec<Download>,
    classpath: Vec<PathBuf>,
    natives: Vec<(PathBuf, Vec<String>)>,
}

/// Queue the jars of the version and of the loader installer; only the version's own go on the classpath.
fn collect_libraries(
    version: &VersionJson,
    installer_libraries: &[Library],
    libraries_dir: &Path,
    progress: &Progress,
) -> Result<Libraries> {
    let mut libraries = Libraries {
        downloads: Vec::new(),
        classpath: Vec::new(),
        natives: Vec::new(),
    };
    let on_classpath = version.libraries.len();
    for (index, library) in version
        .libraries
        .iter()
        .chain(installer_libraries)
        .enumerate()
    {
        if !allows(&library.rules, Features::default()) {
            continue;
        }
        if let Some(artifact) = library_artifact(library)? {
            let path = libraries_dir.join(&artifact.path);
            if index < on_classpath {
                libraries.classpath.push(path.clone());
            }
            // An empty URL means the installer produces the jar; it is checked after processing.
            if !artifact.url.is_empty() {
                progress.add_total(artifact.size.unwrap_or(0));
                libraries.downloads.push(Download {
                    url: artifact.url,
                    path,
                    sha1: artifact.sha1,
                    size: artifact.size,
                    executable: false,
                });
            }
        }
        if let Some(classifier) = native_classifier(library)
            && let Some(artifact) = library
                .downloads
                .as_ref()
                .and_then(|downloads| downloads.classifiers.get(&classifier))
        {
            let name = format!("{}:{classifier}", library.name);
            let path = libraries_dir.join(relative_path(artifact, &name)?);
            libraries
                .downloads
                .push(download(artifact, path.clone(), progress));
            let exclude = library
                .extract
                .as_ref()
                .map(|e| e.exclude.clone())
                .unwrap_or_default();
            libraries.natives.push((path, exclude));
        }
    }
    Ok(libraries)
}

/// Download the asset index and queue every object it lists that is not yet in the cache.
async fn collect_assets(
    downloader: &Downloader,
    assets_dir: &Path,
    asset_index: &FileRef,
    downloads: &mut Vec<Download>,
    progress: &Arc<Progress>,
) -> Result<()> {
    let index_file = assets_dir
        .join("indexes")
        .join(format!("{}.json", asset_index.id));
    downloader
        .fetch(
            &download(asset_index, index_file.clone(), progress),
            progress,
        )
        .await?;
    let index: AssetIndex = read_json(&index_file).await?;
    if index.is_virtual || index.map_to_resources {
        return Err(Error::Unsupported("legacy asset layout"));
    }
    let mut seen = HashSet::new();
    for object in index.objects.values() {
        if !seen.insert(object.hash.as_str()) {
            continue;
        }
        let prefix = object
            .hash
            .get(..2)
            .ok_or_else(|| Error::Malformed(format!("asset hash {}", object.hash)))?;
        progress.add_total(object.size);
        downloads.push(Download {
            url: format!("{ASSET_BASE_URL}/{prefix}/{}", object.hash),
            path: assets_dir.join("objects").join(prefix).join(&object.hash),
            sha1: Some(object.hash.clone()),
            size: Some(object.size),
            executable: false,
        });
    }
    Ok(())
}

/// The fully merged version JSON for an instance: vanilla, or a loader profile on top of vanilla.
/// For Forge-like loaders also returns the installer profile that still has to be processed.
async fn resolve_version(
    store: &Store,
    downloader: &Downloader,
    id: &str,
    instance: &mut Instance,
    cache: &Path,
) -> Result<(VersionJson, Option<(PathBuf, forge::InstallProfile)>)> {
    let game_version = instance.game.version.clone();
    let vanilla_file = cache
        .join("versions")
        .join(&game_version)
        .join(format!("{game_version}.json"));
    fetch_version_json(downloader, &game_version, &vanilla_file).await?;
    let vanilla: VersionJson = read_json(&vanilla_file).await?;

    let kind = instance.loader.kind.clone();
    if kind == loader::VANILLA {
        return Ok((vanilla, None));
    }
    if !loader::is_supported(&kind) {
        return Err(Error::Unsupported("this mod loader"));
    }
    if instance.loader.version.is_empty() {
        // Pin the loader version the first time so the instance stays reproducible.
        instance.loader.version = loader::latest(downloader, &kind, &game_version).await?;
        store.save(id, instance).await?;
    }
    let profile_file = loader::ensure_profile(
        downloader,
        cache,
        &kind,
        &instance.loader.version,
        &game_version,
    )
    .await?;
    let profile: VersionJson = read_json(&profile_file).await?;
    let installer = if loader::is_forge_like(&kind) {
        Some((
            profile_file.clone(),
            forge::load_profile(&profile_file).await?,
        ))
    } else {
        None
    };
    Ok((VersionJson::merge(vanilla, profile), installer))
}

/// Fetch the version JSON by its manifest entry, falling back to a cached copy when offline.
async fn fetch_version_json(downloader: &Downloader, version_id: &str, file: &Path) -> Result<()> {
    let manifest: Result<VersionManifest> = fetch_manifest(downloader).await;
    match manifest {
        Ok(manifest) => {
            let summary = manifest
                .versions
                .iter()
                .find(|version| version.id == version_id)
                .ok_or_else(|| Error::VersionNotFound(version_id.to_owned()))?;
            let request = Download {
                url: summary.url.clone(),
                path: file.to_path_buf(),
                sha1: Some(summary.sha1.clone()),
                size: None,
                executable: false,
            };
            downloader.fetch(&request, &Progress::default()).await
        }
        Err(error) if tokio::fs::try_exists(file).await.unwrap_or(false) => {
            tracing::warn!(%error, url = VERSION_MANIFEST_URL, "manifest unreachable, using cached version json");
            Ok(())
        }
        Err(error) => Err(error),
    }
}

pub(crate) async fn read_json<T: serde::de::DeserializeOwned>(path: &Path) -> Result<T> {
    let text = tokio::fs::read_to_string(path).await.map_err(io(path))?;
    serde_json::from_str(&text).map_err(|source| Error::Json {
        from: path.display().to_string(),
        source,
    })
}

fn download(file: &FileRef, path: PathBuf, progress: &Progress) -> Download {
    progress.add_total(file.size);
    Download {
        url: file.url.clone(),
        path,
        sha1: Some(file.sha1.clone()),
        size: Some(file.size),
        executable: false,
    }
}

struct Artifact {
    path: String,
    url: String,
    sha1: Option<String>,
    size: Option<u64>,
}

/// Where a library's main jar lives: Mojang gives explicit downloads, loaders give a Maven base URL.
fn library_artifact(library: &Library) -> Result<Option<Artifact>> {
    if let Some(artifact) = library.downloads.as_ref().and_then(|d| d.artifact.as_ref()) {
        return Ok(Some(Artifact {
            path: relative_path(artifact, &library.name)?,
            url: artifact.url.clone(),
            sha1: Some(artifact.sha1.clone()),
            size: Some(artifact.size),
        }));
    }
    let Some(base) = &library.url else {
        tracing::debug!(name = %library.name, "library without downloads skipped");
        return Ok(None);
    };
    let path = maven_path(&library.name)
        .ok_or_else(|| Error::Malformed(format!("library name {}", library.name)))?;
    Ok(Some(Artifact {
        url: format!("{}/{path}", base.trim_end_matches('/')),
        path,
        sha1: library.sha1.clone(),
        size: library.size,
    }))
}

fn relative_path(file: &FileRef, name: &str) -> Result<String> {
    let relative = match &file.path {
        Some(path) => path.clone(),
        None => maven_path(name).ok_or_else(|| Error::Malformed(format!("library name {name}")))?,
    };
    if relative.split('/').any(|segment| segment == "..") || relative.starts_with('/') {
        return Err(Error::PathTraversal(relative));
    }
    Ok(relative)
}

/// Pre-1.19 versions list native jars under `natives` keyed by OS, with `${arch}` meaning the bitness.
fn native_classifier(library: &Library) -> Option<String> {
    library
        .natives
        .get(platform::OS_NAME)
        .map(|classifier| classifier.replace("${arch}", "64"))
}

/// Extract a zip into `dest`, skipping `exclude` prefixes and refusing entries that escape.
pub(crate) fn extract(archive: &Path, dest: &Path, exclude: &[String]) -> Result<()> {
    extract_prefix(archive, dest, "", exclude)
}

/// Like `extract`, but only entries under `prefix`, with the prefix removed.
pub(crate) fn extract_prefix(
    archive: &Path,
    dest: &Path,
    prefix: &str,
    exclude: &[String],
) -> Result<()> {
    let file = std::fs::File::open(archive).map_err(io(archive))?;
    let mut zip = zip::ZipArchive::new(file)?;
    for index in 0..zip.len() {
        let mut entry = zip.by_index(index)?;
        let name = entry.name().to_owned();
        let Some(stripped) = name.strip_prefix(prefix) else {
            continue;
        };
        if stripped.is_empty()
            || exclude
                .iter()
                .any(|skip| stripped.starts_with(skip.as_str()))
        {
            continue;
        }
        let Some(relative) = entry.enclosed_name() else {
            return Err(Error::PathTraversal(name));
        };
        let relative: PathBuf = relative
            .components()
            .skip(prefix.matches('/').count())
            .collect();
        let target = dest.join(relative);
        if entry.is_dir() {
            std::fs::create_dir_all(&target).map_err(io(&target))?;
            continue;
        }
        if let Some(parent) = target.parent() {
            std::fs::create_dir_all(parent).map_err(io(parent))?;
        }
        let mut output = std::fs::File::create(&target).map_err(io(&target))?;
        std::io::copy(&mut entry, &mut output).map_err(io(&target))?;
    }
    Ok(())
}

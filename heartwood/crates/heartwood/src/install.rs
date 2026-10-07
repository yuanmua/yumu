//! Bring an instance to a launchable state: version JSON, Java, libraries, client jar, assets, natives.

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
use crate::{java, platform};

/// Everything `launch` needs, all present on disk.
pub struct Prepared {
    pub version: VersionJson,
    pub java: PathBuf,
    pub classpath: Vec<PathBuf>,
    pub natives_dir: PathBuf,
    pub assets_dir: PathBuf,
    pub libraries_dir: PathBuf,
}

pub async fn install(
    store: &Store,
    downloader: &Downloader,
    instance: &Instance,
    progress: &Arc<Progress>,
) -> Result<Prepared> {
    let cache = store.cache_dir();
    let version_id = &instance.game.version;
    let version_dir = cache.join("versions").join(version_id);
    let version_file = version_dir.join(format!("{version_id}.json"));
    fetch_version_json(downloader, version_id, &version_file).await?;
    let version: VersionJson = read_json(&version_file).await?;

    let component = version
        .java_version
        .as_ref()
        .map_or("jre-legacy", |java| java.component.as_str());
    let java = java::ensure_runtime(downloader, &cache, component, progress).await?;

    let libraries_dir = cache.join("libraries");
    let mut downloads = Vec::new();
    let mut classpath = Vec::new();
    let mut natives = Vec::new();
    for library in &version.libraries {
        if !allows(&library.rules, Features::default()) {
            continue;
        }
        let Some(library_downloads) = &library.downloads else {
            tracing::debug!(name = %library.name, "library without downloads skipped");
            continue;
        };
        if let Some(artifact) = &library_downloads.artifact {
            let path = libraries_dir.join(relative_path(artifact, &library.name)?);
            classpath.push(path.clone());
            downloads.push(download(artifact, path, progress));
        }
        if let Some(classifier) = native_classifier(library)
            && let Some(artifact) = library_downloads.classifiers.get(&classifier)
        {
            let name = format!("{}:{classifier}", library.name);
            let path = libraries_dir.join(relative_path(artifact, &name)?);
            downloads.push(download(artifact, path.clone(), progress));
            let exclude = library
                .extract
                .as_ref()
                .map(|e| e.exclude.clone())
                .unwrap_or_default();
            natives.push((path, exclude));
        }
    }

    let client_jar = version_dir.join(format!("{version_id}.jar"));
    downloads.push(download(
        &version.downloads.client,
        client_jar.clone(),
        progress,
    ));
    classpath.push(client_jar);

    let assets_dir = cache.join("assets");
    let index_file = assets_dir
        .join("indexes")
        .join(format!("{}.json", version.asset_index.id));
    downloader
        .fetch(
            &download(&version.asset_index, index_file.clone(), progress),
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

    downloader.fetch_all(downloads, progress).await?;

    let natives_dir = cache.join("natives").join(version_id);
    tokio::fs::create_dir_all(&natives_dir)
        .await
        .map_err(io(&natives_dir))?;
    for (jar, exclude) in natives {
        let dest = natives_dir.clone();
        tokio::task::spawn_blocking(move || extract(&jar, &dest, &exclude)).await??;
    }

    Ok(Prepared {
        version,
        java,
        classpath,
        natives_dir,
        assets_dir,
        libraries_dir,
    })
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

async fn read_json<T: serde::de::DeserializeOwned>(path: &Path) -> Result<T> {
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

fn extract(jar: &Path, dest: &Path, exclude: &[String]) -> Result<()> {
    let file = std::fs::File::open(jar).map_err(io(jar))?;
    let mut archive = zip::ZipArchive::new(file)?;
    for index in 0..archive.len() {
        let mut entry = archive.by_index(index)?;
        let name = entry.name().to_owned();
        if exclude
            .iter()
            .any(|prefix| name.starts_with(prefix.as_str()))
        {
            continue;
        }
        let Some(relative) = entry.enclosed_name() else {
            return Err(Error::PathTraversal(name));
        };
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

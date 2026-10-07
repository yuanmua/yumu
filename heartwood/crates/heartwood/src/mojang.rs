//! Data types for Mojang's version manifest, version JSON, asset index and Java runtime manifest.

use std::collections::HashMap;

use serde::Deserialize;

use crate::download::Downloader;
use crate::error::Result;

pub const VERSION_MANIFEST_URL: &str =
    "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";
pub const JAVA_RUNTIME_MANIFEST_URL: &str = "https://launchermeta.mojang.com/v1/products/java-runtime/2ec0cc96c44e5a76b9c8b7c39df7210883d12871/all.json";
pub const ASSET_BASE_URL: &str = "https://resources.download.minecraft.net";

pub async fn fetch_manifest(downloader: &Downloader) -> Result<VersionManifest> {
    downloader.get_json(VERSION_MANIFEST_URL).await
}

#[derive(Debug, Clone, Deserialize)]
pub struct VersionManifest {
    pub latest: Latest,
    pub versions: Vec<VersionSummary>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Latest {
    pub release: String,
    pub snapshot: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VersionSummary {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub url: String,
    pub sha1: String,
    pub release_time: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VersionJson {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub main_class: String,
    pub assets: String,
    pub asset_index: FileRef,
    pub downloads: Downloads,
    pub libraries: Vec<Library>,
    pub arguments: Option<Arguments>,
    pub minecraft_arguments: Option<String>,
    pub java_version: Option<JavaVersion>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Downloads {
    pub client: FileRef,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FileRef {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub path: Option<String>,
    pub sha1: String,
    pub size: u64,
    pub url: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct JavaVersion {
    pub component: String,
    pub major_version: u32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Library {
    pub name: String,
    #[serde(default)]
    pub downloads: Option<LibraryDownloads>,
    #[serde(default)]
    pub rules: Vec<Rule>,
    #[serde(default)]
    pub natives: HashMap<String, String>,
    #[serde(default)]
    pub extract: Option<Extract>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct LibraryDownloads {
    #[serde(default)]
    pub artifact: Option<FileRef>,
    #[serde(default)]
    pub classifiers: HashMap<String, FileRef>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Extract {
    #[serde(default)]
    pub exclude: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Rule {
    pub action: RuleAction,
    #[serde(default)]
    pub os: Option<OsRule>,
    #[serde(default)]
    pub features: HashMap<String, bool>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RuleAction {
    Allow,
    Disallow,
}

#[derive(Debug, Clone, Deserialize)]
pub struct OsRule {
    pub name: Option<String>,
    pub arch: Option<String>,
    pub version: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Arguments {
    #[serde(default)]
    pub game: Vec<Argument>,
    #[serde(default)]
    pub jvm: Vec<Argument>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub enum Argument {
    Plain(String),
    Conditional { rules: Vec<Rule>, value: Values },
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub enum Values {
    One(String),
    Many(Vec<String>),
}

impl Values {
    pub fn iter(&self) -> impl Iterator<Item = &str> {
        match self {
            Self::One(value) => std::slice::from_ref(value).iter(),
            Self::Many(values) => values.iter(),
        }
        .map(String::as_str)
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct AssetIndex {
    pub objects: HashMap<String, AssetObject>,
    #[serde(default, rename = "virtual")]
    pub is_virtual: bool,
    #[serde(default)]
    pub map_to_resources: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AssetObject {
    pub hash: String,
    pub size: u64,
}

/// `all.json`: platform key → runtime component → available builds.
pub type JavaRuntimeManifest = HashMap<String, HashMap<String, Vec<JavaRuntime>>>;

#[derive(Debug, Clone, Deserialize)]
pub struct JavaRuntime {
    pub manifest: FileRef,
    pub version: JavaRuntimeVersion,
}

#[derive(Debug, Clone, Deserialize)]
pub struct JavaRuntimeVersion {
    pub name: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct JavaFiles {
    pub files: HashMap<String, JavaFile>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum JavaFile {
    File {
        downloads: JavaDownloads,
        #[serde(default)]
        executable: bool,
    },
    Directory,
    Link {
        target: String,
    },
}

#[derive(Debug, Clone, Deserialize)]
pub struct JavaDownloads {
    pub raw: FileRef,
}

/// Relative path of a Maven coordinate such as `org.lwjgl:lwjgl:3.3.3:natives-macos`.
pub fn maven_path(name: &str) -> Option<String> {
    let mut parts = name.split(':');
    let (group, artifact, version) = (parts.next()?, parts.next()?, parts.next()?);
    let classifier = parts.next().map(|c| format!("-{c}")).unwrap_or_default();
    let (version, extension) = version.split_once('@').unwrap_or((version, "jar"));
    Some(format!(
        "{}/{artifact}/{version}/{artifact}-{version}{classifier}.{extension}",
        group.replace('.', "/")
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maven_paths() {
        assert_eq!(
            maven_path("org.lwjgl:lwjgl:3.3.3").as_deref(),
            Some("org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar")
        );
        assert_eq!(
            maven_path("org.lwjgl:lwjgl:3.3.3:natives-macos").as_deref(),
            Some("org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3-natives-macos.jar")
        );
        assert_eq!(maven_path("broken"), None);
    }
}

//! Instances: one directory with an `instance.toml` and a `.minecraft` game directory each.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::error::{Error, Result, io, now};
use crate::platform;

pub const EDITION_JAVA: &str = "java";
const FILE_NAME: &str = "instance.toml";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Instance {
    pub schema: u32,
    pub name: String,
    pub edition: String,
    pub created_at: u64,
    pub last_played_at: u64,
    pub playtime_seconds: u64,
    pub game: Game,
    pub loader: Loader,
    pub java: Java,
    pub memory: Memory,
    pub jvm: Jvm,
    pub window: Window,
    /// Keys this version of Yumu does not know, preserved verbatim.
    #[serde(flatten)]
    pub extra: toml::Table,
}

impl Default for Instance {
    fn default() -> Self {
        Self {
            schema: 1,
            name: String::new(),
            edition: EDITION_JAVA.to_owned(),
            created_at: 0,
            last_played_at: 0,
            playtime_seconds: 0,
            game: Game::default(),
            loader: Loader::default(),
            java: Java::default(),
            memory: Memory::default(),
            jvm: Jvm::default(),
            window: Window::default(),
            extra: toml::Table::new(),
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Game {
    pub version: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Loader {
    pub kind: String,
    pub version: String,
}

impl Default for Loader {
    fn default() -> Self {
        Self {
            kind: "vanilla".to_owned(),
            version: String::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Java {
    pub provider: String,
    pub path: String,
}

impl Default for Java {
    fn default() -> Self {
        Self {
            provider: "mojang".to_owned(),
            path: String::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Memory {
    pub max_mb: u32,
}

impl Default for Memory {
    fn default() -> Self {
        Self { max_mb: 2048 }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Jvm {
    pub extra_args: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Window {
    pub width: u32,
    pub height: u32,
}

impl Default for Window {
    fn default() -> Self {
        Self {
            width: 1280,
            height: 720,
        }
    }
}

/// The data directory and everything inside it.
pub struct Store {
    root: PathBuf,
}

impl Store {
    pub fn open() -> Result<Self> {
        Ok(Self {
            root: platform::data_dir()?,
        })
    }

    pub fn with_root(root: PathBuf) -> Self {
        Self { root }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn cache_dir(&self) -> PathBuf {
        self.root.join("cache")
    }

    pub fn instance_dir(&self, id: &str) -> PathBuf {
        self.root.join("instances").join(id)
    }

    pub fn game_dir(&self, id: &str) -> PathBuf {
        self.instance_dir(id).join(".minecraft")
    }

    /// All instances as `(id, instance)`, sorted by name.
    pub async fn list(&self) -> Result<Vec<(String, Instance)>> {
        let dir = self.root.join("instances");
        tokio::fs::create_dir_all(&dir).await.map_err(io(&dir))?;
        let mut entries = tokio::fs::read_dir(&dir).await.map_err(io(&dir))?;
        let mut instances = Vec::new();
        while let Some(entry) = entries.next_entry().await.map_err(io(&dir))? {
            let id = entry.file_name().to_string_lossy().into_owned();
            if let Ok(instance) = self.load(&id).await {
                instances.push((id, instance));
            }
        }
        instances.sort_by(|a, b| a.1.name.cmp(&b.1.name));
        Ok(instances)
    }

    pub async fn load(&self, id: &str) -> Result<Instance> {
        let path = self.instance_dir(id).join(FILE_NAME);
        let text = match tokio::fs::read_to_string(&path).await {
            Ok(text) => text,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Err(Error::InstanceNotFound(id.to_owned()));
            }
            Err(error) => return Err(io(&path)(error)),
        };
        let instance: Instance = toml::from_str(&text).map_err(|error| Error::Toml {
            path: path.clone(),
            message: error.to_string(),
        })?;
        if instance.edition != EDITION_JAVA {
            return Err(Error::EditionUnsupported(instance.edition));
        }
        Ok(instance)
    }

    pub async fn save(&self, id: &str, instance: &Instance) -> Result<()> {
        let dir = self.instance_dir(id);
        tokio::fs::create_dir_all(&dir).await.map_err(io(&dir))?;
        let path = dir.join(FILE_NAME);
        let part = dir.join("instance.toml.part");
        let text = toml::to_string_pretty(instance).map_err(|error| Error::Toml {
            path: path.clone(),
            message: error.to_string(),
        })?;
        tokio::fs::write(&part, text).await.map_err(io(&part))?;
        tokio::fs::rename(&part, &path).await.map_err(io(&path))
    }

    /// Delete an instance and everything inside it, worlds included.
    pub async fn delete(&self, id: &str) -> Result<()> {
        self.load(id).await?;
        let dir = self.instance_dir(id);
        tokio::fs::remove_dir_all(&dir).await.map_err(io(&dir))
    }

    /// Create an instance and return its id (the directory name).
    pub async fn create(&self, name: &str, game_version: &str) -> Result<String> {
        let id = slug(name);
        let dir = self.instance_dir(&id);
        if tokio::fs::try_exists(&dir).await.unwrap_or(false) {
            return Err(Error::InstanceExists(id));
        }
        let game_dir = self.game_dir(&id);
        tokio::fs::create_dir_all(&game_dir)
            .await
            .map_err(io(&game_dir))?;
        let instance = Instance {
            name: name.to_owned(),
            created_at: now(),
            game: Game {
                version: game_version.to_owned(),
            },
            ..Instance::default()
        };
        self.save(&id, &instance).await?;
        Ok(id)
    }
}

/// Directory-safe form of an instance name. Unicode is kept; only path separators and reserved characters go.
pub fn slug(name: &str) -> String {
    let cleaned: String = name
        .trim()
        .chars()
        .map(|c| {
            if c.is_control() || matches!(c, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|') {
                '-'
            } else {
                c
            }
        })
        .collect();
    if cleaned.is_empty() || cleaned.starts_with('.') {
        "instance".to_owned()
    } else {
        cleaned
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slugs() {
        assert_eq!(slug(" 1.21.1 "), "1.21.1");
        assert_eq!(slug("我的生存"), "我的生存");
        assert_eq!(slug("a/b:c"), "a-b-c");
        assert_eq!(slug("..."), "instance");
        assert_eq!(slug(""), "instance");
    }

    #[test]
    fn toml_round_trip_keeps_unknown_keys() {
        let text = "name = \"x\"\nfuture_key = 1\n\n[game]\nversion = \"1.21\"\n";
        let instance: Instance = toml::from_str(text).unwrap();
        assert_eq!(instance.game.version, "1.21");
        assert_eq!(instance.memory.max_mb, 2048);
        let written = toml::to_string(&instance).unwrap();
        assert!(written.contains("future_key = 1"));
    }
}

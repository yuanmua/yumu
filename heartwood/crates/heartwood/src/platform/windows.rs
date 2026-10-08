use std::path::{Path, PathBuf};

use crate::error::{Error, Result};

pub const OS_NAME: &str = "windows";
pub const CLASSPATH_SEPARATOR: &str = ";";
pub const LEGACY_JVM_ARGS: &[&str] = &[];
pub const JAVA_RUNTIME_PLATFORMS: &[&str] = if cfg!(target_arch = "aarch64") {
    &["windows-arm64", "windows-x64"]
} else if cfg!(target_arch = "x86") {
    &["windows-x86"]
} else {
    &["windows-x64"]
};

pub fn home() -> Result<PathBuf> {
    std::env::var_os("USERPROFILE")
        .map(PathBuf::from)
        .ok_or(Error::NoHome)
}

fn known(variable: &str) -> Result<PathBuf> {
    std::env::var_os(variable)
        .map(PathBuf::from)
        .ok_or(Error::NoHome)
}

pub fn default_data_dir() -> Result<PathBuf> {
    Ok(known("APPDATA")?.join("Yumu"))
}

pub fn log_dir() -> Result<PathBuf> {
    Ok(known("LOCALAPPDATA")?.join("Yumu").join("Logs"))
}

pub fn official_launcher_dir() -> Result<PathBuf> {
    Ok(known("APPDATA")?.join(".minecraft"))
}

pub const JAVA_BINARY: &str = "java.exe";

pub fn other_launcher_dirs() -> Vec<(String, PathBuf)> {
    let Ok(appdata) = known("APPDATA") else {
        return Vec::new();
    };
    [
        ("prism", "PrismLauncher"),
        ("multimc", "MultiMC"),
        ("modrinth", "com.modrinth.theseus"),
    ]
    .iter()
    .map(|(name, dir)| ((*name).to_owned(), appdata.join(dir)))
    .filter(|(_, dir)| dir.is_dir())
    .collect()
}

pub async fn java_homes() -> Vec<PathBuf> {
    let mut homes = Vec::new();
    for root in [
        PathBuf::from(r"C:\Program Files\Java"),
        PathBuf::from(r"C:\Program Files\Eclipse Adoptium"),
        PathBuf::from(r"C:\Program Files\Microsoft"),
        PathBuf::from(r"C:\Program Files\Zulu"),
    ] {
        let Ok(mut entries) = tokio::fs::read_dir(&root).await else {
            continue;
        };
        while let Ok(Some(entry)) = entries.next_entry().await {
            if entry.path().join("bin/java.exe").is_file() {
                homes.push(entry.path());
            }
        }
    }
    homes
}

pub fn java_executable(runtime_dir: &Path) -> PathBuf {
    runtime_dir.join("bin/java.exe")
}

pub fn set_executable(_path: &Path) -> std::io::Result<()> {
    Ok(())
}

/// The data directory lives under the user's profile, which is already private on Windows.
pub fn restrict_permissions(_path: &Path) -> std::io::Result<()> {
    Ok(())
}

pub fn symlink(_target: &str, _link: &Path) -> std::io::Result<()> {
    Ok(())
}

/// Nothing to do: a child process is not tied to its parent on Windows unless it joins a job object.
pub fn detach(_command: &mut tokio::process::Command) {}

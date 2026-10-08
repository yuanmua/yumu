use std::path::{Path, PathBuf};

use crate::error::{Error, Result};

pub const OS_NAME: &str = "linux";
pub const CLASSPATH_SEPARATOR: &str = ":";
pub const LEGACY_JVM_ARGS: &[&str] = &[];
pub const JAVA_RUNTIME_PLATFORMS: &[&str] = if cfg!(target_arch = "x86_64") {
    &["linux"]
} else if cfg!(target_arch = "x86") {
    &["linux-i386"]
} else {
    &[]
};

pub fn home() -> Result<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or(Error::NoHome)
}

fn xdg(variable: &str, fallback: &str) -> Result<PathBuf> {
    match std::env::var_os(variable) {
        Some(dir) => Ok(PathBuf::from(dir).join("yumu")),
        None => Ok(home()?.join(fallback).join("yumu")),
    }
}

pub fn default_data_dir() -> Result<PathBuf> {
    xdg("XDG_DATA_HOME", ".local/share")
}

pub fn log_dir() -> Result<PathBuf> {
    Ok(xdg("XDG_STATE_HOME", ".local/state")?.join("logs"))
}

pub fn official_launcher_dir() -> Result<PathBuf> {
    Ok(home()?.join(".minecraft"))
}

pub const JAVA_BINARY: &str = "java";

pub fn other_launcher_dirs() -> Vec<(String, PathBuf)> {
    let Ok(data) = xdg("XDG_DATA_HOME", ".local/share")
        .map(|d| d.parent().map(Path::to_path_buf).unwrap_or(d))
    else {
        return Vec::new();
    };
    [
        ("prism", "PrismLauncher"),
        ("multimc", "multimc"),
        ("modrinth", "ModrinthApp"),
    ]
    .iter()
    .map(|(name, dir)| ((*name).to_owned(), data.join(dir)))
    .filter(|(_, dir)| dir.is_dir())
    .collect()
}

pub async fn java_homes() -> Vec<PathBuf> {
    let mut homes = Vec::new();
    for root in ["/usr/lib/jvm", "/usr/lib64/jvm", "/opt"] {
        let Ok(mut entries) = tokio::fs::read_dir(root).await else {
            continue;
        };
        while let Ok(Some(entry)) = entries.next_entry().await {
            if entry.path().join("bin/java").is_file() {
                homes.push(entry.path());
            }
        }
    }
    homes
}

pub fn java_executable(runtime_dir: &Path) -> PathBuf {
    runtime_dir.join("bin/java")
}

pub fn set_executable(path: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755))
}

/// Owner-only permissions for files holding tokens.
pub fn restrict_permissions(path: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))
}

pub fn symlink(target: &str, link: &Path) -> std::io::Result<()> {
    std::os::unix::fs::symlink(target, link)
}

pub fn detach(command: &mut tokio::process::Command) {
    command.process_group(0);
}

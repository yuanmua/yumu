use std::path::{Path, PathBuf};

use crate::error::{Error, Result};

pub const OS_NAME: &str = "osx";
pub const CLASSPATH_SEPARATOR: &str = ":";
/// JVM flags for versions whose JSON predates per-OS argument rules.
pub const LEGACY_JVM_ARGS: &[&str] = &["-XstartOnFirstThread"];
/// Mojang runtime platform keys, most specific first.
pub const JAVA_RUNTIME_PLATFORMS: &[&str] = if cfg!(target_arch = "aarch64") {
    &["mac-os-arm64", "mac-os"]
} else {
    &["mac-os"]
};

pub fn home() -> Result<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or(Error::NoHome)
}

pub fn default_data_dir() -> Result<PathBuf> {
    Ok(home()?.join("Library/Application Support/Yumu"))
}

pub fn log_dir() -> Result<PathBuf> {
    Ok(home()?.join("Library/Logs/Yumu"))
}

pub fn official_launcher_dir() -> Result<PathBuf> {
    Ok(home()?.join("Library/Application Support/minecraft"))
}

pub fn java_executable(runtime_dir: &Path) -> PathBuf {
    runtime_dir.join("jre.bundle/Contents/Home/bin/java")
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

/// Put the game in its own process group so it outlives the launcher.
pub fn detach(command: &mut tokio::process::Command) {
    command.process_group(0);
}

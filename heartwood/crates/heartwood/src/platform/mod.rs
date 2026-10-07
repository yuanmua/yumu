//! Everything that differs between operating systems. Business code never uses `cfg`.

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
pub use macos::*;

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
pub use linux::*;

#[cfg(target_os = "windows")]
mod windows;
#[cfg(target_os = "windows")]
pub use windows::*;

use std::path::PathBuf;

use crate::error::Result;

/// Architecture name as used by Mojang's `os.arch` rules.
pub const ARCH: &str = if cfg!(target_arch = "x86_64") {
    "x86_64"
} else if cfg!(target_arch = "aarch64") {
    "arm64"
} else if cfg!(target_arch = "x86") {
    "x86"
} else {
    std::env::consts::ARCH
};

/// Data directory, honouring the `YUMU_DATA_DIR` override.
pub fn data_dir() -> Result<PathBuf> {
    match std::env::var_os("YUMU_DATA_DIR") {
        Some(dir) => Ok(dir.into()),
        None => default_data_dir(),
    }
}

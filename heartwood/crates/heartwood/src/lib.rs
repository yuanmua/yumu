//! Heartwood is the core of the Yumu Minecraft launcher: everything except the user interface.
#![cfg_attr(test, allow(clippy::unwrap_used, clippy::expect_used))]

pub mod account;
pub mod download;
pub mod error;
pub mod install;
pub mod instance;
pub mod java;
pub mod launch;
pub mod mojang;
pub mod platform;
pub mod rules;

pub use error::{Error, Result};

/// Version of the core library.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

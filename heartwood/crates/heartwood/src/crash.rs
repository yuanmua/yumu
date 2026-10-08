//! Turn a failed game session into one of a handful of causes a player can act on.

use std::path::{Path, PathBuf};

use serde::Serialize;

use crate::error::io;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Crash {
    /// `OUT_OF_MEMORY`, `JAVA_VERSION`, `NATIVES`, `MOD_DEPENDENCY`, `MOD_CONFLICT`, `GRAPHICS` or `UNKNOWN`.
    pub kind: &'static str,
    /// The log lines that decided the classification, for the "show details" view.
    pub detail: Vec<String>,
    /// Mod names mentioned in those lines, when the loader printed any.
    pub mods: Vec<String>,
    pub report_path: Option<PathBuf>,
}

/// Classification rules, first match wins. Patterns are matched case-sensitively on each line.
const RULES: &[(&str, &[&str])] = &[
    (
        "OUT_OF_MEMORY",
        &["OutOfMemoryError", "Out of memory", "GC overhead limit"],
    ),
    (
        "JAVA_VERSION",
        &[
            "UnsupportedClassVersionError",
            "class file version",
            "more recent version of the Java Runtime",
            "requires Java",
        ],
    ),
    (
        "NATIVES",
        &["UnsatisfiedLinkError", "Can't load library", "no lwjgl"],
    ),
    (
        "MOD_DEPENDENCY",
        &[
            "Unmet dependency",
            "Mod resolution failed",
            "requires version",
            "Missing or unsupported mandatory dependencies",
            "which is missing",
            "Mod loading has failed",
        ],
    ),
    (
        "MOD_CONFLICT",
        &[
            "Incompatible mods found",
            "is incompatible with",
            "DuplicateModsFoundException",
            "Duplicate mod",
            "MixinApplyError",
            "Mixin apply failed",
            "MixinTransformerError",
        ],
    ),
    (
        "GRAPHICS",
        &[
            "GLFW error",
            "Failed to create window",
            "Pixel format not accelerated",
            "No OpenGL context",
            "GL_INVALID",
        ],
    ),
];

/// Classify a session from its log tail and, when one appeared, the crash report.
pub fn analyze(log: &str, report: Option<&str>) -> Crash {
    let text = format!("{}\n{log}", report.unwrap_or_default());
    for (kind, patterns) in RULES {
        let detail: Vec<String> = text
            .lines()
            .filter(|line| patterns.iter().any(|pattern| line.contains(pattern)))
            .map(|line| line.trim().chars().take(240).collect())
            .take(4)
            .collect();
        if !detail.is_empty() {
            let mods = quoted_names(&detail);
            return Crash {
                kind,
                detail,
                mods,
                report_path: None,
            };
        }
    }
    let detail = text
        .lines()
        .filter(|line| {
            line.contains("Exception") || line.contains("Error") || line.contains("FATAL")
        })
        .map(|line| line.trim().chars().take(240).collect())
        .take(4)
        .collect();
    Crash {
        kind: "UNKNOWN",
        detail,
        mods: Vec::new(),
        report_path: None,
    }
}

/// Read what the session left behind and classify it. `started_at` separates this run's crash report from older ones.
pub async fn analyze_session(
    game_dir: &Path,
    log_file: &Path,
    started_at: std::time::SystemTime,
) -> Crash {
    let log = tail(log_file, 256 * 1024).await.unwrap_or_default();
    let report_path = newest_report(&game_dir.join("crash-reports"), started_at).await;
    let report = match &report_path {
        Some(path) => tail(path, 64 * 1024).await.ok(),
        None => None,
    };
    let mut crash = analyze(&log, report.as_deref());
    crash.report_path = report_path;
    crash
}

async fn tail(path: &Path, max: u64) -> crate::Result<String> {
    use tokio::io::{AsyncReadExt, AsyncSeekExt};
    let mut file = tokio::fs::File::open(path).await.map_err(io(path))?;
    let len = file.metadata().await.map_err(io(path))?.len();
    if len > max {
        file.seek(std::io::SeekFrom::Start(len - max))
            .await
            .map_err(io(path))?;
    }
    let mut bytes = Vec::new();
    file.read_to_end(&mut bytes).await.map_err(io(path))?;
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}

async fn newest_report(dir: &Path, started_at: std::time::SystemTime) -> Option<PathBuf> {
    let mut entries = tokio::fs::read_dir(dir).await.ok()?;
    let mut newest: Option<(std::time::SystemTime, PathBuf)> = None;
    while let Ok(Some(entry)) = entries.next_entry().await {
        let Ok(modified) = entry.metadata().await.and_then(|m| m.modified()) else {
            continue;
        };
        if modified >= started_at && newest.as_ref().is_none_or(|(time, _)| modified > *time) {
            newest = Some((modified, entry.path()));
        }
    }
    newest.map(|(_, path)| path)
}

/// Loaders quote mod names: `Mod 'Sodium Extra' (sodium-extra) requires version 0.6 of 'sodium'`.
fn quoted_names(lines: &[String]) -> Vec<String> {
    let mut names = Vec::new();
    for line in lines {
        let mut parts = line.split('\'');
        parts.next();
        while let (Some(name), Some(_)) = (parts.next(), parts.next()) {
            if !name.is_empty() && name.len() < 64 && !names.contains(&name.to_owned()) {
                names.push(name.to_owned());
            }
        }
    }
    names.truncate(6);
    names
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classifies_common_failures() {
        assert_eq!(
            analyze("java.lang.OutOfMemoryError: Java heap space", None).kind,
            "OUT_OF_MEMORY"
        );
        assert_eq!(
            analyze(
                "Exception: UnsupportedClassVersionError: class file version 65.0",
                None
            )
            .kind,
            "JAVA_VERSION"
        );
        let fabric = analyze(
            "net.fabricmc.loader.impl.FormattedException: Mod resolution failed\n - Mod 'Sodium Extra' (sodium-extra) 0.6.0 requires version 0.6 or later of 'sodium', which is missing!",
            None,
        );
        assert_eq!(fabric.kind, "MOD_DEPENDENCY");
        assert_eq!(fabric.mods, vec!["Sodium Extra", "sodium"]);
        assert_eq!(
            analyze(
                "[main/ERROR]: GLFW error 65542: WGL: The driver does not appear to support OpenGL",
                None
            )
            .kind,
            "GRAPHICS"
        );
        assert_eq!(
            analyze(
                "Exception in thread main java.lang.NullPointerException",
                None
            )
            .kind,
            "UNKNOWN"
        );
    }

    #[test]
    fn report_outranks_log_noise() {
        let report = "---- Minecraft Crash Report ----\njava.lang.OutOfMemoryError: Metaspace";
        assert_eq!(
            analyze("GLFW error 1234 while closing", Some(report)).kind,
            "OUT_OF_MEMORY"
        );
    }
}

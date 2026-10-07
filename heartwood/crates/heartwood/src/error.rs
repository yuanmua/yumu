use std::path::{Path, PathBuf};

/// Every failure the core can report. Each variant maps to exactly one Grain error kind.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("io error at {path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("request to {url} failed: {source}")]
    Http {
        url: String,
        #[source]
        source: reqwest::Error,
    },
    #[error("unexpected status {status} from {url}")]
    HttpStatus { url: String, status: u16 },
    #[error("hash mismatch for {path}: expected {expected}, got {actual}")]
    HashMismatch {
        path: PathBuf,
        expected: String,
        actual: String,
    },
    #[error("invalid json from {from}: {source}")]
    Json {
        from: String,
        #[source]
        source: serde_json::Error,
    },
    #[error("invalid toml at {path}: {message}")]
    Toml { path: PathBuf, message: String },
    #[error("malformed data: {0}")]
    Malformed(String),
    #[error("game version {0} not found")]
    VersionNotFound(String),
    #[error("instance {0} not found")]
    InstanceNotFound(String),
    #[error("instance {0} already exists")]
    InstanceExists(String),
    #[error("edition {0} is not supported")]
    EditionUnsupported(String),
    #[error("no java runtime {component} is available for this platform")]
    JavaUnavailable { component: String },
    #[error("{0} is not supported")]
    Unsupported(&'static str),
    #[error("entry {0} escapes its target directory")]
    PathTraversal(String),
    #[error("zip error: {0}")]
    Zip(#[from] zip::result::ZipError),
    #[error("background task failed: {0}")]
    Join(#[from] tokio::task::JoinError),
    #[error("failed to start the game: {0}")]
    Spawn(#[source] std::io::Error),
    #[error("operation cancelled")]
    Cancelled,
    #[error("home directory not found")]
    NoHome,
}

impl Error {
    /// Stable identifier used by user interfaces to look up a translated message.
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Io { .. } => "IO",
            Self::Http { .. } => "HTTP",
            Self::HttpStatus { .. } => "HTTP_STATUS",
            Self::HashMismatch { .. } => "DOWNLOAD_HASH_MISMATCH",
            Self::Json { .. } => "INVALID_JSON",
            Self::Toml { .. } => "INVALID_TOML",
            Self::Malformed(_) => "MALFORMED_DATA",
            Self::VersionNotFound(_) => "VERSION_NOT_FOUND",
            Self::InstanceNotFound(_) => "INSTANCE_NOT_FOUND",
            Self::InstanceExists(_) => "INSTANCE_EXISTS",
            Self::EditionUnsupported(_) => "INSTANCE_EDITION_UNSUPPORTED",
            Self::JavaUnavailable { .. } => "JAVA_UNAVAILABLE",
            Self::Unsupported(_) => "UNSUPPORTED",
            Self::PathTraversal(_) => "PATH_TRAVERSAL",
            Self::Zip(_) => "ZIP",
            Self::Join(_) | Self::Cancelled => "CANCELLED",
            Self::Spawn(_) => "GAME_SPAWN_FAILED",
            Self::NoHome => "NO_HOME_DIRECTORY",
        }
    }
}

pub type Result<T> = std::result::Result<T, Error>;

pub(crate) fn io(path: &Path) -> impl FnOnce(std::io::Error) -> Error + '_ {
    move |source| Error::Io {
        path: path.to_path_buf(),
        source,
    }
}

pub(crate) fn now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_secs())
}

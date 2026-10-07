//! Method dispatch and the JSON shapes that cross the C boundary.

use std::sync::Arc;
use std::time::Instant;

use heartwood::download::Progress;
use heartwood::mojang::fetch_manifest;
use heartwood::{Error, Result, account, install, launch};
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::{Value, json};

use crate::core::{Core, lock};

const ASYNC_METHODS: &[&str] = &["version.listGame", "instance.launch"];

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct IdParams {
    id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct CreateParams {
    name: String,
    game_version: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LaunchParams {
    id: String,
    player_name: String,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct VersionParams {
    snapshots: bool,
}

pub(crate) fn check_async(method: &str) -> Result<()> {
    if ASYNC_METHODS.contains(&method) {
        Ok(())
    } else {
        Err(Error::InvalidRequest(format!(
            "{method} is not an asynchronous method"
        )))
    }
}

pub(crate) async fn call(core: &Core, method: &str, params: Value) -> Result<Value> {
    match method {
        "grain.ping" => Ok(json!({ "pong": true })),
        "instance.list" => list(core).await,
        "instance.create" => {
            let params: CreateParams = parse(params)?;
            let id = core
                .store
                .create(&params.name, &params.game_version)
                .await?;
            core.emit("instance.changed", json!({ "id": id, "change": "created" }));
            Ok(json!({ "id": id }))
        }
        "instance.delete" => {
            let params: IdParams = parse(params)?;
            core.store.delete(&params.id).await?;
            core.emit(
                "instance.changed",
                json!({ "id": params.id, "change": "deleted" }),
            );
            Ok(json!({}))
        }
        _ => Err(Error::InvalidRequest(format!("unknown method {method}"))),
    }
}

pub(crate) async fn start(
    core: &Arc<Core>,
    method: &str,
    params: Value,
    progress: &Arc<Progress>,
) -> Result<Value> {
    match method {
        "version.listGame" => {
            let params: VersionParams = parse(params)?;
            let manifest = fetch_manifest(&core.downloader).await?;
            let versions: Vec<Value> = manifest
                .versions
                .iter()
                .filter(|version| params.snapshots || version.kind == "release")
                .map(|version| {
                    json!({ "id": version.id, "kind": version.kind, "releaseTime": version.release_time })
                })
                .collect();
            Ok(json!({ "latestRelease": manifest.latest.release, "versions": versions }))
        }
        "instance.launch" => launch_instance(core, parse(params)?, progress).await,
        _ => Err(Error::InvalidRequest(format!("unknown method {method}"))),
    }
}

async fn list(core: &Core) -> Result<Value> {
    let running = lock(&core.running).clone();
    let instances = core.store.list().await?;
    let summaries: Vec<Value> = instances
        .iter()
        .map(|(id, instance)| {
            json!({
                "id": id,
                "name": instance.name,
                "gameVersion": instance.game.version,
                "loaderKind": instance.loader.kind,
                "lastPlayedAt": instance.last_played_at,
                "playtimeSeconds": instance.playtime_seconds,
                "running": running.contains_key(id),
            })
        })
        .collect();
    Ok(Value::Array(summaries))
}

/// Install whatever is missing, start the game, and keep watching it until it exits.
async fn launch_instance(
    core: &Arc<Core>,
    params: LaunchParams,
    progress: &Arc<Progress>,
) -> Result<Value> {
    let id = params.id;
    let mut instance = core.store.load(&id).await?;
    let prepared = install::install(&core.store, &core.downloader, &instance, progress).await?;
    let account = account::offline(&params.player_name);
    let launched = launch::launch(&core.store, &id, &mut instance, &prepared, &account).await?;
    let pid = launched.child.id().unwrap_or(0);
    lock(&core.running).insert(id.clone(), pid);
    core.emit("game.started", json!({ "instanceId": id, "pid": pid }));

    let core = Arc::clone(core);
    let watched = id.clone();
    tokio::spawn(async move {
        let started = Instant::now();
        let mut child = launched.child;
        let status = child.wait().await;
        lock(&core.running).remove(&watched);
        if let Ok(mut instance) = core.store.load(&watched).await {
            instance.playtime_seconds += started.elapsed().as_secs();
            if let Err(error) = core.store.save(&watched, &instance).await {
                tracing::warn!(%error, "could not record playtime");
            }
        }
        let exit_code = status.ok().and_then(|status| status.code());
        core.emit(
            "game.exited",
            json!({ "instanceId": watched, "code": exit_code }),
        );
        core.emit(
            "instance.changed",
            json!({ "id": watched, "change": "updated" }),
        );
    });
    Ok(json!({ "pid": pid }))
}

fn parse<T: DeserializeOwned>(params: Value) -> Result<T> {
    serde_json::from_value(params).map_err(|error| Error::InvalidRequest(error.to_string()))
}

pub(crate) fn error_json(error: &Error) -> Value {
    json!({ "kind": error.kind(), "args": args(error), "detail": error.to_string() })
}

fn args(error: &Error) -> Value {
    match error {
        Error::Io { path, .. } | Error::Toml { path, .. } => json!({ "path": path }),
        Error::Http { url, .. } => json!({ "url": url }),
        Error::HttpStatus { url, status } => json!({ "url": url, "status": status }),
        Error::HashMismatch {
            path,
            expected,
            actual,
        } => {
            json!({ "path": path, "expected": expected, "actual": actual })
        }
        Error::Json { from, .. } => json!({ "from": from }),
        Error::Malformed(detail) | Error::InvalidRequest(detail) => json!({ "detail": detail }),
        Error::VersionNotFound(version) => json!({ "version": version }),
        Error::InstanceNotFound(id) | Error::InstanceExists(id) => json!({ "id": id }),
        Error::EditionUnsupported(edition) => json!({ "edition": edition }),
        Error::JavaUnavailable { component } => json!({ "component": component }),
        Error::Unsupported(what) => json!({ "what": what }),
        Error::PathTraversal(entry) => json!({ "entry": entry }),
        _ => json!({}),
    }
}

//! Method dispatch and the JSON shapes that cross the C boundary.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

use heartwood::download::Progress;
use heartwood::mojang::fetch_manifest;
use heartwood::resource::Kind;
use heartwood::{Error, Result, account, auth, install, launch, loader, modpack, mods, resource};
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::{Value, json};

use crate::core::{Core, lock};

const ASYNC_METHODS: &[&str] = &[
    "version.listGame",
    "version.listLoader",
    "instance.launch",
    "account.beginMicrosoftLogin",
    "mod.search",
    "mod.install",
    "resource.install",
    "modpack.search",
    "modpack.import",
    "modpack.installModrinth",
];

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
    #[serde(default)]
    loader_kind: Option<String>,
    #[serde(default)]
    loader_version: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LaunchParams {
    id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct NameParams {
    name: String,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct VersionParams {
    snapshots: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LoaderVersionParams {
    game_version: String,
    loader: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SearchParams {
    #[serde(default)]
    id: Option<String>,
    #[serde(default = "default_project_type")]
    project_type: String,
    #[serde(default)]
    query: String,
    #[serde(default)]
    offset: u32,
}

fn default_project_type() -> String {
    "mod".to_owned()
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProjectParams {
    project_id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ModInstallParams {
    id: String,
    project_id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct FileParams {
    id: String,
    file_name: String,
    #[serde(default)]
    enabled: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ResourceParams {
    id: String,
    kind: String,
    #[serde(default)]
    file_name: String,
    #[serde(default)]
    enabled: bool,
    #[serde(default)]
    path: PathBuf,
    #[serde(default)]
    project_id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PackParams {
    path: PathBuf,
    #[serde(default)]
    name: Option<String>,
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
    if ASYNC_METHODS.contains(&method) {
        return Err(Error::InvalidRequest(format!(
            "{method} must be started with grain_start"
        )));
    }
    match method {
        "grain.ping" => Ok(json!({ "pong": true })),
        "instance.list" => list(core).await,
        "instance.create" => {
            let params: CreateParams = parse(params)?;
            let id = core
                .store
                .create(&params.name, &params.game_version)
                .await?;
            if let Some(kind) = params.loader_kind.filter(|kind| kind != loader::VANILLA) {
                if !loader::is_supported(&kind) {
                    core.store.delete(&id).await?;
                    return Err(Error::Unsupported("this mod loader"));
                }
                let mut instance = core.store.load(&id).await?;
                instance.loader.kind = kind;
                instance.loader.version = params.loader_version.unwrap_or_default();
                core.store.save(&id, &instance).await?;
            }
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
        _ => call_accounts(core, method, params).await,
    }
}

/// Synchronous account methods. Offline accounts follow Prism's rule: only alongside a Microsoft one.
async fn call_accounts(core: &Core, method: &str, params: Value) -> Result<Value> {
    let mut accounts = core.store.load_accounts().await?;
    match method {
        "account.list" => {
            return Ok(json!(accounts
                .accounts
                .iter()
                .map(|a| json!({ "id": a.id, "kind": a.kind, "name": a.name, "uuid": a.uuid, "active": a.id == accounts.active }))
                .collect::<Vec<_>>()));
        }
        "account.addOffline" => {
            let params: NameParams = parse(params)?;
            accounts.add_offline(params.name.trim())?;
        }
        "account.remove" => accounts.remove(&parse::<IdParams>(params)?.id)?,
        "account.setActive" => accounts.set_active(&parse::<IdParams>(params)?.id)?,
        _ => return call_files(core, method, params).await,
    }
    core.store.save_accounts(&accounts).await?;
    core.emit("account.changed", json!({ "active": accounts.active }));
    Ok(json!({ "active": accounts.active }))
}

/// Synchronous methods that only touch files inside an instance.
async fn call_files(core: &Core, method: &str, params: Value) -> Result<Value> {
    match method {
        "mod.listInstalled" => {
            let params: IdParams = parse(params)?;
            let mods =
                mods::list(&core.store.game_dir(&params.id), &core.store.cache_dir()).await?;
            to_value(&mods)
        }
        "mod.toggle" => {
            let params: FileParams = parse(params)?;
            mods::set_enabled(
                &core.store.game_dir(&params.id),
                &params.file_name,
                params.enabled,
            )
            .await?;
            Ok(json!({}))
        }
        "mod.remove" => {
            let params: FileParams = parse(params)?;
            mods::remove(&core.store.game_dir(&params.id), &params.file_name).await?;
            Ok(json!({}))
        }
        "resource.list" => {
            let params: ResourceParams = parse(params)?;
            let files =
                resource::list(&core.store.game_dir(&params.id), Kind::parse(&params.kind)?)
                    .await?;
            to_value(&files)
        }
        "resource.add" => {
            let params: ResourceParams = parse(params)?;
            let name = resource::add(
                &core.store.game_dir(&params.id),
                Kind::parse(&params.kind)?,
                &params.path,
            )
            .await?;
            Ok(json!({ "fileName": name }))
        }
        "resource.remove" => {
            let params: ResourceParams = parse(params)?;
            resource::remove(
                &core.store.game_dir(&params.id),
                Kind::parse(&params.kind)?,
                &params.file_name,
            )
            .await?;
            Ok(json!({}))
        }
        "resource.toggle" => {
            let params: ResourceParams = parse(params)?;
            let game_dir = core.store.game_dir(&params.id);
            resource::set_enabled(
                &game_dir,
                Kind::parse(&params.kind)?,
                &params.file_name,
                params.enabled,
            )
            .await?;
            Ok(json!({}))
        }
        "modpack.inspect" => {
            let params: PackParams = parse(params)?;
            let summary =
                tokio::task::spawn_blocking(move || modpack::inspect(&params.path)).await??;
            to_value(&summary)
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
        "version.listLoader" => {
            let params: LoaderVersionParams = parse(params)?;
            let versions =
                loader::list_versions(&core.downloader, &params.loader, &params.game_version)
                    .await?;
            Ok(json!(
                versions
                    .iter()
                    .map(|v| json!({ "version": v.version, "stable": v.stable }))
                    .collect::<Vec<_>>()
            ))
        }
        "instance.launch" => launch_instance(core, parse(params)?, progress).await,
        "account.beginMicrosoftLogin" => {
            let device = auth::begin_device_code(&core.downloader).await?;
            core.emit(
                "account.loginCode",
                json!({ "userCode": device.user_code, "verificationUri": device.verification_uri }),
            );
            let signed = auth::finish_device_code(&core.downloader, &device).await?;
            let added = account::from_signed(signed);
            let mut accounts = core.store.load_accounts().await?;
            accounts.upsert(added.clone());
            core.store.save_accounts(&accounts).await?;
            core.emit("account.changed", json!({}));
            Ok(json!({ "id": added.id, "name": added.name }))
        }
        _ => start_content(core, method, params, progress).await,
    }
}

/// Asynchronous methods about mods, resources and modpacks.
async fn start_content(
    core: &Arc<Core>,
    method: &str,
    params: Value,
    progress: &Arc<Progress>,
) -> Result<Value> {
    match method {
        "mod.search" | "modpack.search" => {
            let params: SearchParams = parse(params)?;
            let project_type = if method == "modpack.search" {
                "modpack"
            } else {
                params.project_type.as_str()
            };
            let instance = match &params.id {
                Some(id) => Some(core.store.load(id).await?),
                None => None,
            };
            let result = mods::search(
                &core.downloader,
                project_type,
                &params.query,
                instance.as_ref().map(|i| i.game.version.as_str()),
                instance.as_ref().map(|i| i.loader.kind.as_str()),
                params.offset,
            )
            .await?;
            to_value(&result)
        }
        "resource.install" => {
            let params: ResourceParams = parse(params)?;
            let instance = core.store.load(&params.id).await?;
            let dir = core
                .store
                .game_dir(&params.id)
                .join(Kind::parse(&params.kind)?.dir_name());
            tokio::fs::create_dir_all(&dir)
                .await
                .map_err(|source| Error::Io {
                    path: dir.clone(),
                    source,
                })?;
            let file_name = mods::install_file(
                &core.downloader,
                &dir,
                &params.project_id,
                Some(&instance.game.version),
                progress,
            )
            .await?;
            Ok(json!({ "fileName": file_name }))
        }
        "modpack.installModrinth" => {
            let params: ProjectParams = parse(params)?;
            let id = modpack::import_from_modrinth(
                &core.store,
                &core.downloader,
                &params.project_id,
                progress,
            )
            .await?;
            core.emit("instance.changed", json!({ "id": id, "change": "created" }));
            Ok(json!({ "id": id }))
        }
        "mod.install" => {
            let params: ModInstallParams = parse(params)?;
            let instance = core.store.load(&params.id).await?;
            let installed = mods::install(
                &core.downloader,
                &core.store.game_dir(&params.id),
                &core.store.cache_dir(),
                &params.project_id,
                &instance.game.version,
                &instance.loader.kind,
                progress,
            )
            .await?;
            core.emit(
                "instance.changed",
                json!({ "id": params.id, "change": "updated" }),
            );
            to_value(&installed)
        }
        "modpack.import" => {
            let params: PackParams = parse(params)?;
            let id = modpack::import(
                &core.store,
                &core.downloader,
                &params.path,
                params.name.as_deref(),
                progress,
            )
            .await?;
            core.emit("instance.changed", json!({ "id": id, "change": "created" }));
            Ok(json!({ "id": id }))
        }
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
                "loaderVersion": instance.loader.version,
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
    let session = account::active_session(&core.store, &core.downloader).await?;
    let prepared =
        install::install(&core.store, &core.downloader, &id, &mut instance, progress).await?;
    let launched = launch::launch(&core.store, &id, &mut instance, &prepared, &session).await?;
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

fn to_value<T: serde::Serialize>(value: &T) -> Result<Value> {
    serde_json::to_value(value).map_err(|error| Error::Malformed(error.to_string()))
}

pub(crate) fn error_json(error: &Error) -> Value {
    json!({ "kind": error.kind(), "args": args(error), "detail": error.to_string() })
}

fn args(error: &Error) -> Value {
    match error {
        Error::Io { path, .. } | Error::Toml { path, .. } => json!({ "path": path }),
        Error::Http { url, .. } | Error::HostNotAllowed { url } => json!({ "url": url }),
        Error::HttpStatus { url, status } => json!({ "url": url, "status": status }),
        Error::HashMismatch {
            path,
            expected,
            actual,
        } => {
            json!({ "path": path, "expected": expected, "actual": actual })
        }
        Error::Json { from, .. } => json!({ "from": from }),
        Error::Malformed(detail) | Error::InvalidRequest(detail) | Error::AuthFailed(detail) => {
            json!({ "detail": detail })
        }
        Error::LoaderInstallFailed { step, detail } => json!({ "step": step, "detail": detail }),
        Error::VersionNotFound(version) => json!({ "version": version }),
        Error::InstanceNotFound(id) | Error::InstanceExists(id) | Error::AccountNotFound(id) => {
            json!({ "id": id })
        }
        Error::EditionUnsupported(edition) => json!({ "edition": edition }),
        Error::JavaUnavailable { component } => json!({ "component": component }),
        Error::Unsupported(what) => json!({ "what": what }),
        Error::PathTraversal(entry) => json!({ "entry": entry }),
        Error::ModNotCompatible {
            project,
            game_version,
            loader,
        } => {
            json!({ "project": project, "gameVersion": game_version, "loader": loader })
        }
        Error::InvalidFileName(name) => json!({ "name": name }),
        _ => json!({}),
    }
}

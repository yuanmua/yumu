//! Build the command line and start the game as a detached process logging to a file.

use std::path::PathBuf;
use std::process::Stdio;

use crate::account::Session;
use crate::error::{Error, Result, io, now};
use crate::install::Prepared;
use crate::instance::{Instance, Store};
use crate::mojang::Argument;
use crate::rules::{Features, allows};
use crate::{VERSION, platform};

const LOGS_TO_KEEP: usize = 20;

pub struct Launched {
    pub child: tokio::process::Child,
    pub log_file: PathBuf,
}

pub async fn launch(
    store: &Store,
    id: &str,
    instance: &mut Instance,
    prepared: &Prepared,
    session: &Session,
) -> Result<Launched> {
    let game_dir = store.game_dir(id);
    tokio::fs::create_dir_all(&game_dir)
        .await
        .map_err(io(&game_dir))?;
    let logs_dir = store.instance_dir(id).join("logs");
    tokio::fs::create_dir_all(&logs_dir)
        .await
        .map_err(io(&logs_dir))?;
    prune_logs(&logs_dir).await?;
    let log_file = logs_dir.join(format!("{}.log", now()));
    let log = std::fs::File::create(&log_file).map_err(io(&log_file))?;
    let log_err = log.try_clone().map_err(io(&log_file))?;

    let classpath = prepared
        .classpath
        .iter()
        .map(|path| path.display().to_string())
        .collect::<Vec<_>>()
        .join(platform::CLASSPATH_SEPARATOR);
    let version = &prepared.version;
    let natives = prepared.natives_dir.display().to_string();
    let assets = prepared.assets_dir.display().to_string();
    let variables = [
        ("auth_player_name", session.name.clone()),
        ("auth_uuid", session.uuid.clone()),
        ("auth_access_token", session.access_token.clone()),
        ("user_type", session.user_type.clone()),
        ("clientid", "0".to_owned()),
        ("auth_xuid", session.xuid.clone()),
        ("version_name", version.id.clone()),
        ("version_type", version.kind.clone()),
        ("game_directory", game_dir.display().to_string()),
        ("assets_root", assets.clone()),
        ("game_assets", assets),
        ("assets_index_name", prepared.asset_index_id.clone()),
        ("resolution_width", instance.window.width.to_string()),
        ("resolution_height", instance.window.height.to_string()),
        ("natives_directory", natives.clone()),
        (
            "library_directory",
            prepared.libraries_dir.display().to_string(),
        ),
        ("launcher_name", "yumu".to_owned()),
        ("launcher_version", VERSION.to_owned()),
        ("classpath", classpath.clone()),
        (
            "classpath_separator",
            platform::CLASSPATH_SEPARATOR.to_owned(),
        ),
    ];
    let features = Features {
        custom_resolution: true,
    };

    let mut jvm_args = vec![format!("-Xmx{}M", instance.memory.max_mb)];
    jvm_args.extend(instance.jvm.extra_args.iter().cloned());
    let game_args = match (&version.arguments, &version.minecraft_arguments) {
        (Some(arguments), _) => {
            jvm_args.extend(expand(&arguments.jvm, features, &variables));
            expand(&arguments.game, features, &variables)
        }
        (None, Some(legacy)) => {
            jvm_args.extend(platform::LEGACY_JVM_ARGS.iter().map(ToString::to_string));
            jvm_args.push(format!("-Djava.library.path={natives}"));
            jvm_args.push("-cp".to_owned());
            jvm_args.push(classpath);
            legacy
                .split_whitespace()
                .map(|argument| substitute(argument, &variables))
                .collect()
        }
        (None, None) => return Err(Error::Malformed("version json has no arguments".to_owned())),
    };

    let mut command = tokio::process::Command::new(&prepared.java);
    command
        .args(&jvm_args)
        .arg(&version.main_class)
        .args(&game_args)
        .current_dir(&game_dir)
        .stdin(Stdio::null())
        .stdout(Stdio::from(log))
        .stderr(Stdio::from(log_err));
    platform::detach(&mut command);
    tracing::debug!(java = %prepared.java.display(), ?jvm_args, ?game_args, "starting game");
    let child = command.spawn().map_err(Error::Spawn)?;
    tracing::info!(pid = child.id(), version = %version.id, "game started");

    instance.last_played_at = now();
    store.save(id, instance).await?;
    Ok(Launched { child, log_file })
}

fn expand(arguments: &[Argument], features: Features, variables: &[(&str, String)]) -> Vec<String> {
    let mut out = Vec::new();
    for argument in arguments {
        match argument {
            Argument::Plain(value) => out.push(substitute(value, variables)),
            Argument::Conditional { rules, value } if allows(rules, features) => {
                out.extend(value.iter().map(|v| substitute(v, variables)));
            }
            Argument::Conditional { .. } => {}
        }
    }
    out
}

fn substitute(template: &str, variables: &[(&str, String)]) -> String {
    let mut result = template.to_owned();
    for (name, value) in variables {
        result = result.replace(&format!("${{{name}}}"), value);
    }
    result
}

async fn prune_logs(logs_dir: &std::path::Path) -> Result<()> {
    let mut entries = tokio::fs::read_dir(logs_dir).await.map_err(io(logs_dir))?;
    let mut logs = Vec::new();
    while let Some(entry) = entries.next_entry().await.map_err(io(logs_dir))? {
        logs.push(entry.path());
    }
    logs.sort();
    for old in logs.iter().rev().skip(LOGS_TO_KEEP - 1) {
        tokio::fs::remove_file(old).await.map_err(io(old))?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn substitutes_all_placeholders() {
        let variables = [("a", "1".to_owned()), ("b", "2".to_owned())];
        assert_eq!(substitute("${a}-${b}-${c}", &variables), "1-2-${c}");
    }
}

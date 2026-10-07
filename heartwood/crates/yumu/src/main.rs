use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::Context;
use clap::{Parser, Subcommand};
use heartwood::download::{Downloader, Progress};
use heartwood::instance::{Store, slug};
use heartwood::{Error, account, install, launch, mojang};
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;

#[derive(Parser)]
#[command(name = "yumu", version, about = "A small Minecraft launcher")]
struct Cli {
    /// Show debug logs
    #[arg(long, global = true)]
    verbose: bool,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Install what is missing and start the game
    Play {
        /// Game version, defaults to the latest release
        #[arg(long)]
        version: Option<String>,
        /// Instance name, defaults to the version
        #[arg(long)]
        name: Option<String>,
        /// Offline player name
        #[arg(long, default_value = "Player")]
        player: String,
        /// Return immediately instead of waiting for the game to exit
        #[arg(long)]
        detach: bool,
    },
    /// Manage instances
    Instance {
        #[command(subcommand)]
        command: InstanceCommand,
    },
    /// List available game versions
    Version {
        /// Include snapshots
        #[arg(long)]
        snapshots: bool,
    },
}

#[derive(Subcommand)]
enum InstanceCommand {
    /// List instances
    List,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    let level = if cli.verbose {
        tracing::Level::DEBUG
    } else {
        tracing::Level::WARN
    };
    let filter = tracing_subscriber::filter::Targets::new()
        .with_target("heartwood", level)
        .with_target("yumu", level);
    tracing_subscriber::fmt()
        .with_writer(std::io::stderr)
        .finish()
        .with(filter)
        .init();

    let store = Store::open()?;
    let downloader = Downloader::new(16)?;
    match cli.command {
        Command::Play {
            version,
            name,
            player,
            detach,
        } => play(&store, &downloader, version, name, &player, detach).await,
        Command::Instance {
            command: InstanceCommand::List,
        } => {
            for (id, instance) in store.list().await? {
                println!("{id}\t{}\t{}", instance.game.version, instance.name);
            }
            Ok(())
        }
        Command::Version { snapshots } => {
            let manifest = mojang::fetch_manifest(&downloader).await?;
            for version in manifest
                .versions
                .iter()
                .filter(|v| snapshots || v.kind == "release")
            {
                println!("{}\t{}\t{}", version.id, version.kind, version.release_time);
            }
            Ok(())
        }
    }
}

async fn play(
    store: &Store,
    downloader: &Downloader,
    version: Option<String>,
    name: Option<String>,
    player: &str,
    detach: bool,
) -> anyhow::Result<()> {
    let (name, version) = match (name, version) {
        (Some(name), version) => (name, version),
        (None, version) => {
            let version = resolve_version(downloader, version).await?;
            (version.clone(), Some(version))
        }
    };
    let id = slug(&name);
    let mut instance = match store.load(&id).await {
        Ok(instance) => instance,
        Err(Error::InstanceNotFound(_)) => {
            let version = resolve_version(downloader, version).await?;
            store.create(&name, &version).await?;
            store.load(&id).await?
        }
        Err(error) => return Err(error.into()),
    };
    println!("Instance: {} ({})", instance.name, instance.game.version);

    let progress = Arc::new(Progress::default());
    let reporter = tokio::spawn(report(Arc::clone(&progress)));
    let prepared = install::install(store, downloader, &instance, &progress).await;
    reporter.abort();
    println!();
    let prepared = prepared.context("installation failed")?;

    let account = account::offline(player);
    let launched = launch::launch(store, &id, &mut instance, &prepared, &account).await?;
    println!(
        "Game started (pid {}). Log: {}",
        launched.child.id().unwrap_or_default(),
        launched.log_file.display()
    );
    if detach {
        return Ok(());
    }

    let started = Instant::now();
    let mut child = launched.child;
    let status = child.wait().await.context("waiting for the game")?;
    instance.playtime_seconds += started.elapsed().as_secs();
    store.save(&id, &instance).await?;
    println!("Game exited: {status}");
    Ok(())
}

async fn resolve_version(
    downloader: &Downloader,
    version: Option<String>,
) -> anyhow::Result<String> {
    match version {
        Some(version) => Ok(version),
        None => Ok(mojang::fetch_manifest(downloader).await?.latest.release),
    }
}

async fn report(progress: Arc<Progress>) {
    let mut interval = tokio::time::interval(Duration::from_millis(200));
    loop {
        interval.tick().await;
        let (done, total) = (progress.done() >> 20, progress.total() >> 20);
        eprint!("\rDownloading {done} / {total} MiB   ");
    }
}

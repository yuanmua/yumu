use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::Context;
use clap::{Parser, Subcommand};
use heartwood::download::{Downloader, Progress};
use heartwood::instance::{Store, slug};
use heartwood::{Error, account, auth, install, launch, modpack, mods, mojang};
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
        /// Mod loader for a new instance: vanilla, fabric or quilt
        #[arg(long, default_value = "vanilla")]
        loader: String,
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
    /// Manage mods of an instance
    Mod {
        #[command(subcommand)]
        command: ModCommand,
    },
    /// Import modpacks
    Modpack {
        #[command(subcommand)]
        command: ModpackCommand,
    },
    /// Manage accounts
    Account {
        #[command(subcommand)]
        command: AccountCommand,
    },
    /// Find worlds, versions and Java runtimes already on this computer
    Discover,
}

#[derive(Subcommand)]
enum AccountCommand {
    /// List accounts
    List,
    /// Sign in with a Microsoft account
    Login,
    /// Add an offline account (requires a Microsoft account first)
    Offline { name: String },
    /// Make an account active
    Use { id: String },
    /// Remove an account
    Remove { id: String },
}

#[derive(Subcommand)]
enum ModCommand {
    /// List installed mods
    List { instance: String },
    /// Search Modrinth for mods compatible with the instance
    Search { instance: String, query: String },
    /// Install a Modrinth project (by id or slug) and its required dependencies
    Install { instance: String, project: String },
}

#[derive(Subcommand)]
enum ModpackCommand {
    /// Create an instance from a .mrpack file
    Import {
        path: PathBuf,
        #[arg(long)]
        name: Option<String>,
    },
}

#[derive(Subcommand)]
enum InstanceCommand {
    /// List instances
    List,
    /// Create an instance without starting it
    Create {
        name: String,
        #[arg(long)]
        version: String,
        #[arg(long, default_value = "vanilla")]
        loader: String,
    },
    /// Download everything an instance needs without starting it
    Install { name: String },
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
            loader,
            detach,
        } => play(&store, &downloader, version, name, &loader, detach).await,
        Command::Instance { command } => run_instance(&store, &downloader, command).await,
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
        Command::Mod { command } => run_mod(&store, &downloader, command).await,
        Command::Account { command } => run_account(&store, &downloader, command).await,
        Command::Discover => {
            let scan = heartwood::discover::scan().await?;
            for installation in &scan.installations {
                println!("{}\t{}", installation.launcher, installation.path.display());
                for version in &installation.versions {
                    println!(
                        "  version\t{}\t{} {} {}",
                        version.id,
                        version.game_version,
                        version.loader_kind,
                        version.loader_version
                    );
                }
                for save in &installation.saves {
                    println!("  save\t{}\t{}", save.name, save.path.display());
                }
            }
            for java in &scan.java {
                println!("java\t{}\t{}", java.version, java.path.display());
            }
            Ok(())
        }
        Command::Modpack {
            command: ModpackCommand::Import { path, name },
        } => {
            let progress = Arc::new(Progress::default());
            let reporter = tokio::spawn(report(Arc::clone(&progress)));
            let result =
                modpack::import(&store, &downloader, &path, name.as_deref(), &progress).await;
            reporter.abort();
            println!();
            println!("Imported as instance {}", result?);
            Ok(())
        }
    }
}

async fn run_instance(
    store: &Store,
    downloader: &Downloader,
    command: InstanceCommand,
) -> anyhow::Result<()> {
    match command {
        InstanceCommand::List => {
            for (id, instance) in store.list().await? {
                println!(
                    "{id}\t{}\t{}\t{}",
                    instance.game.version, instance.loader.kind, instance.name
                );
            }
        }
        InstanceCommand::Create {
            name,
            version,
            loader,
        } => {
            let id = store.create(&name, &version).await?;
            if loader != heartwood::loader::VANILLA {
                let mut created = store.load(&id).await?;
                created.loader.kind = loader;
                store.save(&id, &created).await?;
            }
            println!("Created {id}");
        }
        InstanceCommand::Install { name } => {
            let id = slug(&name);
            let mut instance = store.load(&id).await?;
            let progress = Arc::new(Progress::default());
            let reporter = tokio::spawn(report(Arc::clone(&progress)));
            let result = install::install(store, downloader, &id, &mut instance, &progress).await;
            reporter.abort();
            println!();
            let prepared = result.context("installation failed")?;
            println!(
                "Ready: {} with {} classpath entries",
                prepared.version.id,
                prepared.classpath.len()
            );
        }
    }
    Ok(())
}

async fn run_account(
    store: &Store,
    downloader: &Downloader,
    command: AccountCommand,
) -> anyhow::Result<()> {
    let mut accounts = store.load_accounts().await?;
    match command {
        AccountCommand::List => {
            for account in &accounts.accounts {
                let marker = if account.id == accounts.active {
                    "*"
                } else {
                    " "
                };
                println!(
                    "{marker} {}\t{}\t{}\t{}",
                    account.kind, account.name, account.uuid, account.id
                );
            }
            return Ok(());
        }
        AccountCommand::Login => {
            let code = auth::begin_device_code(downloader).await?;
            println!(
                "Open {} and enter the code {}",
                code.verification_uri, code.user_code
            );
            let signed = auth::finish_device_code(downloader, &code).await?;
            println!("Signed in as {}", signed.name);
            accounts.upsert(account::from_signed(signed));
        }
        AccountCommand::Offline { name } => {
            accounts.add_offline(&name)?;
        }
        AccountCommand::Use { id } => accounts.set_active(&id)?,
        AccountCommand::Remove { id } => accounts.remove(&id)?,
    }
    store.save_accounts(&accounts).await?;
    Ok(())
}

async fn run_mod(
    store: &Store,
    downloader: &Downloader,
    command: ModCommand,
) -> anyhow::Result<()> {
    match command {
        ModCommand::List { instance } => {
            let id = slug(&instance);
            for m in mods::list(&store.game_dir(&id), &store.cache_dir()).await? {
                let state = if m.enabled { "on" } else { "off" };
                let source = m
                    .record
                    .map_or(String::new(), |r| format!("modrinth:{}", r.project_id));
                println!(
                    "{state}\t{}\t{}\t{}\t{source}",
                    m.name, m.version, m.file_name
                );
            }
            Ok(())
        }
        ModCommand::Search { instance, query } => {
            let target = store.load(&slug(&instance)).await?;
            let result = mods::search(
                downloader,
                "mod",
                &query,
                Some(&target.game.version),
                Some(&target.loader.kind),
                0,
            )
            .await?;
            for hit in result.hits {
                println!(
                    "{}\t{}\t{}\t{}",
                    hit.slug, hit.title, hit.downloads, hit.description
                );
            }
            Ok(())
        }
        ModCommand::Install { instance, project } => {
            let id = slug(&instance);
            let target = store.load(&id).await?;
            let progress = Arc::new(Progress::default());
            let reporter = tokio::spawn(report(Arc::clone(&progress)));
            let result = mods::install(
                downloader,
                &store.game_dir(&id),
                &store.cache_dir(),
                &project,
                &target.game.version,
                &target.loader.kind,
                &progress,
            )
            .await;
            reporter.abort();
            println!();
            for record in result? {
                println!("Installed {} {}", record.title, record.version_number);
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
    loader: &str,
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
            let mut created = store.load(&id).await?;
            if loader != heartwood::loader::VANILLA {
                created.loader.kind = loader.to_owned();
                store.save(&id, &created).await?;
            }
            created
        }
        Err(error) => return Err(error.into()),
    };
    println!("Instance: {} ({})", instance.name, instance.game.version);

    let session = account::active_session(store, downloader)
        .await
        .context("run `yumu account login` first")?;
    let progress = Arc::new(Progress::default());
    let reporter = tokio::spawn(report(Arc::clone(&progress)));
    let prepared = install::install(store, downloader, &id, &mut instance, &progress).await;
    reporter.abort();
    println!();
    let prepared = prepared.context("installation failed")?;

    let launched = launch::launch(store, &id, &mut instance, &prepared, &session).await?;
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
    let started_at = std::time::SystemTime::now();
    let status = child.wait().await.context("waiting for the game")?;
    instance.playtime_seconds += started.elapsed().as_secs();
    store.save(&id, &instance).await?;
    println!("Game exited: {status}");
    if status.code().is_some_and(|code| code != 0) {
        let crash =
            heartwood::crash::analyze_session(&store.game_dir(&id), &launched.log_file, started_at)
                .await;
        println!("Crash: {} {:?}", crash.kind, crash.mods);
        for line in crash.detail {
            println!("  {line}");
        }
    }
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

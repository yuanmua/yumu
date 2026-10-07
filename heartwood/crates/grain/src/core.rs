//! The long-lived core object behind a `GrainCore` handle: runtime, store, tasks and events.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::Duration;

use heartwood::download::{Downloader, Progress};
use heartwood::instance::Store;
use heartwood::{Error, Result};
use serde::Deserialize;
use serde_json::{Value, json};
use tokio::task::AbortHandle;

use crate::methods;

pub type EventSink = Arc<dyn Fn(&str) + Send + Sync>;

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Config {
    pub data_dir: Option<String>,
    pub concurrency: Option<usize>,
}

pub struct Core {
    runtime: tokio::runtime::Runtime,
    pub(crate) store: Arc<Store>,
    pub(crate) downloader: Downloader,
    events: EventSink,
    tasks: Mutex<HashMap<String, AbortHandle>>,
    /// Instance id → pid of the running game.
    pub(crate) running: Mutex<HashMap<String, u32>>,
    next_task: AtomicU64,
}

impl Core {
    pub fn new(config: Config, events: EventSink) -> Result<Self> {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .map_err(Error::Runtime)?;
        let store = match config.data_dir {
            Some(dir) => Store::with_root(dir.into()),
            None => Store::open()?,
        };
        Ok(Self {
            runtime,
            store: Arc::new(store),
            downloader: Downloader::new(config.concurrency.unwrap_or(16))?,
            events,
            tasks: Mutex::new(HashMap::new()),
            running: Mutex::new(HashMap::new()),
            next_task: AtomicU64::new(0),
        })
    }

    pub(crate) fn emit(&self, topic: &str, payload: Value) {
        let mut event = serde_json::Map::new();
        event.insert("topic".into(), topic.into());
        event.insert("payload".into(), payload);
        (self.events)(&Value::Object(event).to_string());
    }

    /// Run a synchronous method on the calling thread.
    pub fn call(&self, method: &str, params: Value) -> Result<Value> {
        self.runtime.block_on(methods::call(self, method, params))
    }

    /// Start an asynchronous method; its outcome arrives as task events.
    pub fn start(self: &Arc<Self>, method: &str, params: Value) -> Result<String> {
        methods::check_async(method)?;
        let task_id = format!(
            "task-{}",
            self.next_task.fetch_add(1, Ordering::Relaxed) + 1
        );
        let core = Arc::clone(self);
        let method = method.to_owned();
        let id = task_id.clone();
        let task = self.runtime.spawn(async move {
            let progress = Arc::new(Progress::default());
            let reporter =
                tokio::spawn(report(Arc::clone(&core), id.clone(), Arc::clone(&progress)));
            let result = methods::start(&core, &method, params, &progress).await;
            reporter.abort();
            lock(&core.tasks).remove(&id);
            match result {
                Ok(value) => core.emit("task.completed", json!({ "taskId": id, "result": value })),
                Err(error) => core.emit(
                    "task.failed",
                    json!({ "taskId": id, "error": methods::error_json(&error) }),
                ),
            }
        });
        lock(&self.tasks).insert(task_id.clone(), task.abort_handle());
        Ok(task_id)
    }

    pub fn cancel(&self, task_id: &str) -> bool {
        let Some(task) = lock(&self.tasks).remove(task_id) else {
            return false;
        };
        task.abort();
        self.emit("task.cancelled", json!({ "taskId": task_id }));
        true
    }
}

async fn report(core: Arc<Core>, task_id: String, progress: Arc<Progress>) {
    let mut interval = tokio::time::interval(Duration::from_millis(100));
    let mut last = 0;
    loop {
        interval.tick().await;
        let (done, total) = (progress.done(), progress.total());
        if total > 0 && done != last {
            last = done;
            core.emit(
                "task.progress",
                json!({ "taskId": task_id, "bytesDone": done, "bytesTotal": total }),
            );
        }
    }
}

pub(crate) fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

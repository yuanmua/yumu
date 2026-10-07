//! C ABI of the Yumu core. The header `include/grain.h` is the contract; keep both in sync.
#![cfg_attr(test, allow(clippy::unwrap_used, clippy::expect_used))]

mod core;
mod methods;

use std::ffi::{CStr, CString, c_char, c_void};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr::null_mut;
use std::sync::{Arc, Mutex};

use heartwood::Error;
use serde_json::{Value, json};

pub use core::{Config, Core};

/// Callback receiving every event as a JSON document.
pub type GrainEventFn = unsafe extern "C" fn(json: *const c_char, user_data: *mut c_void);

/// Opaque handle handed to the host application.
pub struct GrainCore {
    core: Arc<Core>,
}

struct Sink {
    callback: GrainEventFn,
    user_data: *mut c_void,
}

// The host promises `user_data` may be used from any thread; that is the contract of a C callback.
unsafe impl Send for Sink {}
unsafe impl Sync for Sink {}

static LAST_INIT_ERROR: Mutex<Option<CString>> = Mutex::new(None);
const API_VERSION: &CStr = c"0.1.0";
const VERSION: &CStr =
    match CStr::from_bytes_with_nul(concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes()) {
        Ok(version) => version,
        Err(_) => c"0.0.0",
    };

/// # Safety
/// `config_json` must be NULL or a valid NUL-terminated string. `user_data` must stay valid until `grain_shutdown`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn grain_init(
    config_json: *const c_char,
    on_event: Option<GrainEventFn>,
    user_data: *mut c_void,
) -> *mut GrainCore {
    let result = catch_unwind(|| -> Result<GrainCore, String> {
        let config: Config = match unsafe { text(config_json) } {
            Some(text) => serde_json::from_str(text).map_err(|error| error.to_string())?,
            None => Config::default(),
        };
        let sink = on_event.map(|callback| Sink {
            callback,
            user_data,
        });
        let core = Core::new(
            config,
            Arc::new(move |message: &str| emit(sink.as_ref(), message)),
        )
        .map_err(|error| error.to_string())?;
        Ok(GrainCore {
            core: Arc::new(core),
        })
    });
    match result {
        Ok(Ok(core)) => Box::into_raw(Box::new(core)),
        Ok(Err(message)) => fail_init(&message),
        Err(_) => fail_init("panic during initialisation"),
    }
}

fn emit(sink: Option<&Sink>, message: &str) {
    if let Some(sink) = sink
        && let Ok(message) = CString::new(message)
    {
        unsafe { (sink.callback)(message.as_ptr(), sink.user_data) }
    }
}

fn fail_init(message: &str) -> *mut GrainCore {
    let mut last = LAST_INIT_ERROR
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    *last = CString::new(message).ok();
    null_mut()
}

/// # Safety
/// `core` must come from `grain_init` and not be used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn grain_shutdown(core: *mut GrainCore) {
    if !core.is_null() {
        drop(unsafe { Box::from_raw(core) });
    }
}

/// # Safety
/// `core` must come from `grain_init`; strings must be NULL or valid NUL-terminated.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn grain_call(
    core: *const GrainCore,
    method: *const c_char,
    params_json: *const c_char,
) -> *mut c_char {
    respond(|| {
        let core = unsafe { handle(core) }?;
        let method = unsafe { text(method) }
            .ok_or_else(|| Error::InvalidRequest("missing method".into()))?;
        core.call(method, unsafe { params(params_json) }?)
    })
}

/// # Safety
/// Same as `grain_call`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn grain_start(
    core: *const GrainCore,
    method: *const c_char,
    params_json: *const c_char,
) -> *mut c_char {
    respond(|| {
        let core = unsafe { handle(core) }?;
        let method = unsafe { text(method) }
            .ok_or_else(|| Error::InvalidRequest("missing method".into()))?;
        let task_id = core.start(method, unsafe { params(params_json) }?)?;
        Ok(json!({ "taskId": task_id }))
    })
}

/// # Safety
/// Same as `grain_call`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn grain_cancel(
    core: *const GrainCore,
    task_id: *const c_char,
) -> *mut c_char {
    respond(|| {
        let core = unsafe { handle(core) }?;
        let task_id = unsafe { text(task_id) }
            .ok_or_else(|| Error::InvalidRequest("missing task id".into()))?;
        Ok(json!({ "cancelled": core.cancel(task_id) }))
    })
}

/// # Safety
/// `s` must be NULL or a string returned by this library that has not been freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn grain_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(unsafe { CString::from_raw(s) });
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn grain_version() -> *const c_char {
    VERSION.as_ptr()
}

#[unsafe(no_mangle)]
pub extern "C" fn grain_api_version() -> *const c_char {
    API_VERSION.as_ptr()
}

#[unsafe(no_mangle)]
pub extern "C" fn grain_last_init_error() -> *const c_char {
    let last = LAST_INIT_ERROR
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    last.as_ref()
        .map_or(c"".as_ptr(), |message| message.as_ptr())
}

unsafe fn handle<'a>(core: *const GrainCore) -> heartwood::Result<&'a Arc<Core>> {
    unsafe { core.as_ref() }
        .map(|wrapper| &wrapper.core)
        .ok_or_else(|| Error::InvalidRequest("null core".into()))
}

unsafe fn text<'a>(pointer: *const c_char) -> Option<&'a str> {
    if pointer.is_null() {
        None
    } else {
        unsafe { CStr::from_ptr(pointer) }.to_str().ok()
    }
}

unsafe fn params(pointer: *const c_char) -> heartwood::Result<Value> {
    match unsafe { text(pointer) } {
        None => Ok(Value::Object(serde_json::Map::new())),
        Some(text) => {
            serde_json::from_str(text).map_err(|error| Error::InvalidRequest(error.to_string()))
        }
    }
}

fn respond(operation: impl FnOnce() -> heartwood::Result<Value>) -> *mut c_char {
    let document = match catch_unwind(AssertUnwindSafe(operation)) {
        Ok(Ok(value)) => json!({ "ok": value }),
        Ok(Err(error)) => json!({ "err": methods::error_json(&error) }),
        Err(_) => json!({ "err": { "kind": "INTERNAL", "args": {}, "detail": "panic" } }),
    };
    CString::new(document.to_string()).map_or(null_mut(), CString::into_raw)
}

#[cfg(test)]
mod tests {
    use std::ffi::CString;
    use std::sync::Mutex;

    use super::*;

    unsafe extern "C" fn collect(json: *const c_char, user_data: *mut c_void) {
        let events = unsafe { &*user_data.cast::<Mutex<Vec<String>>>() };
        let text = unsafe { CStr::from_ptr(json) }
            .to_string_lossy()
            .into_owned();
        events.lock().unwrap().push(text);
    }

    fn call(core: *const GrainCore, method: &str, params: &str) -> Value {
        let method = CString::new(method).unwrap();
        let params = CString::new(params).unwrap();
        let raw = unsafe { grain_call(core, method.as_ptr(), params.as_ptr()) };
        let text = unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_owned();
        unsafe { grain_string_free(raw) };
        serde_json::from_str(&text).unwrap()
    }

    #[test]
    fn instance_round_trip_over_the_c_abi() {
        let data_dir = std::env::temp_dir().join(format!("yumu-grain-test-{}", std::process::id()));
        let config = CString::new(json!({ "dataDir": data_dir }).to_string()).unwrap();
        let events: Box<Mutex<Vec<String>>> = Box::default();
        let user_data = std::ptr::from_ref(&*events).cast_mut().cast::<c_void>();
        let core = unsafe { grain_init(config.as_ptr(), Some(collect), user_data) };
        assert!(
            !core.is_null(),
            "{}",
            unsafe { CStr::from_ptr(grain_last_init_error()) }.to_string_lossy()
        );

        assert_eq!(call(core, "instance.list", "{}"), json!({ "ok": [] }));
        let created = call(
            core,
            "instance.create",
            r#"{"name":"Test","gameVersion":"1.21.1"}"#,
        );
        assert_eq!(created["ok"]["id"], "Test");
        let listed = call(core, "instance.list", "{}");
        assert_eq!(listed["ok"][0]["gameVersion"], "1.21.1");
        assert_eq!(listed["ok"][0]["running"], false);
        assert_eq!(
            call(core, "instance.delete", r#"{"id":"Test"}"#),
            json!({ "ok": {} })
        );
        assert_eq!(
            call(core, "instance.delete", r#"{"id":"Test"}"#)["err"]["kind"],
            "INSTANCE_NOT_FOUND"
        );
        assert_eq!(call(core, "nope", "{}")["err"]["kind"], "INVALID_REQUEST");

        unsafe { grain_shutdown(core) };
        assert_eq!(
            events.lock().unwrap().len(),
            2,
            "one instance.changed per create and delete"
        );
        std::fs::remove_dir_all(data_dir).unwrap();
    }
}

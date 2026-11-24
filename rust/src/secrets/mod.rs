//! Secret storage: where the app keeps its secrets, seen from Rust.
//!
//! On Android the Kotlin `SecretStore` encrypts them with a key held in the Android Keystore;
//! Dart hands Rust three callbacks that reach it ([`Keystore`]). Elsewhere (desktop builds exist
//! only for development) there is no keystore, so they fall back to a plain JSON file in the app
//! config directory. Never ship that: it is not encrypted.
//!
//! Only the feature modules that need a secret (see `api::identity`) reach this; Dart never
//! reads one except through the explicit backup export.

use flutter_rust_bridge::DartFnFuture;
use std::{
    collections::HashMap,
    fs,
    path::PathBuf,
    sync::{Arc, Mutex, OnceLock},
};

type GetFn = Arc<dyn Fn(String) -> DartFnFuture<Option<String>> + Send + Sync>;
type SetFn = Arc<dyn Fn(String, String) -> DartFnFuture<String> + Send + Sync>;
type DeleteFn = Arc<dyn Fn(String) -> DartFnFuture<()> + Send + Sync>;

/// The Android Keystore, reached through Dart.
#[derive(Clone)]
pub struct Keystore {
    pub get: GetFn,
    /// Returns an empty string on success, otherwise the reason it failed.
    pub set: SetFn,
    pub delete: DeleteFn,
}

enum Backend {
    Keystore(Keystore),
    /// Development only: not encrypted.
    DevFile(PathBuf),
}

static BACKEND: OnceLock<Mutex<Option<Arc<Backend>>>> = OnceLock::new();
/// Serializes read-modify-write of the dev file.
static DEV_LOCK: Mutex<()> = Mutex::new(());

fn slot() -> &'static Mutex<Option<Arc<Backend>>> {
    BACKEND.get_or_init(|| Mutex::new(None))
}

/// Chooses the backend. Called once at startup; calling it again replaces the choice.
pub fn configure(config_dir: &str, keystore: Option<Keystore>) {
    let backend = match keystore {
        Some(k) => Backend::Keystore(k),
        None => Backend::DevFile(PathBuf::from(config_dir).join("dev-secrets.json")),
    };
    *slot().lock().unwrap() = Some(Arc::new(backend));
}

fn backend() -> Result<Arc<Backend>, String> {
    slot().lock().unwrap().clone().ok_or_else(|| "the app core is not initialised".to_string())
}

fn read_dev(path: &PathBuf) -> Result<HashMap<String, String>, String> {
    match fs::read_to_string(path) {
        Ok(text) => serde_json::from_str(&text).map_err(|e| e.to_string()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(HashMap::new()),
        Err(e) => Err(e.to_string()),
    }
}

fn write_dev(path: &PathBuf, secrets: &HashMap<String, String>) -> Result<(), String> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    fs::write(path, serde_json::to_string(secrets).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o600)).map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub async fn get(key: &str) -> Result<Option<String>, String> {
    match &*backend()? {
        Backend::Keystore(k) => Ok((k.get)(key.to_string()).await),
        Backend::DevFile(path) => {
            let _guard = DEV_LOCK.lock().unwrap();
            Ok(read_dev(path)?.remove(key))
        }
    }
}

pub async fn set(key: &str, value: &str) -> Result<(), String> {
    match &*backend()? {
        Backend::Keystore(k) => match (k.set)(key.to_string(), value.to_string()).await {
            e if e.is_empty() => Ok(()),
            e => Err(e),
        },
        Backend::DevFile(path) => {
            let _guard = DEV_LOCK.lock().unwrap();
            let mut secrets = read_dev(path)?;
            secrets.insert(key.into(), value.into());
            write_dev(path, &secrets)
        }
    }
}

pub async fn delete(key: &str) -> Result<(), String> {
    match &*backend()? {
        Backend::Keystore(k) => {
            (k.delete)(key.to_string()).await;
            Ok(())
        }
        Backend::DevFile(path) => {
            let _guard = DEV_LOCK.lock().unwrap();
            let mut secrets = read_dev(path)?;
            secrets.remove(key);
            write_dev(path, &secrets)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn block<T>(f: impl std::future::Future<Output = T>) -> T {
        // The dev backend never awaits, so a tiny executor is enough.
        use std::task::{Context, Poll, RawWaker, RawWakerVTable, Waker};
        fn noop(_: *const ()) {}
        fn clone(_: *const ()) -> RawWaker {
            RawWaker::new(std::ptr::null(), &VTABLE)
        }
        static VTABLE: RawWakerVTable = RawWakerVTable::new(clone, noop, noop, noop);
        let waker = unsafe { Waker::from_raw(RawWaker::new(std::ptr::null(), &VTABLE)) };
        let mut cx = Context::from_waker(&waker);
        let mut f = Box::pin(f);
        loop {
            if let Poll::Ready(v) = f.as_mut().poll(&mut cx) {
                return v;
            }
        }
    }

    #[test]
    fn the_dev_file_backend_stores_reads_and_deletes() {
        let dir = std::env::temp_dir().join(format!("pania-secrets-{}", std::process::id()));
        configure(dir.to_str().unwrap(), None);
        assert_eq!(block(get("k")).unwrap(), None);
        block(set("k", "v")).unwrap();
        assert_eq!(block(get("k")).unwrap().as_deref(), Some("v"));
        block(delete("k")).unwrap();
        assert_eq!(block(get("k")).unwrap(), None);
        let _ = fs::remove_dir_all(dir);
    }
}

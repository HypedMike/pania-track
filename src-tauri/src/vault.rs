//! Where the app keeps its secrets, from the Rust side.
//!
//! On Android the `secret-store` plugin encrypts them with a key held in the Android Keystore.
//! Elsewhere (desktop builds exist only for development) there is no keystore, so they fall
//! back to a plain JSON file in the app config directory. Never ship that: it is not encrypted.
//! The webview has no permission to call the plugin directly; only the commands in
//! `identity_commands.rs` reach it.

use std::{collections::HashMap, fs, path::PathBuf};
use tauri::{AppHandle, Manager, Runtime};
use tauri_plugin_secret_store::{Error as StoreError, KeyArgs, SecretStore, SetArgs};

fn dev_file<R: Runtime>(app: &AppHandle<R>) -> Result<PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("dev-secrets.json"))
}

fn read_dev<R: Runtime>(app: &AppHandle<R>) -> Result<HashMap<String, String>, String> {
    match fs::read_to_string(dev_file(app)?) {
        Ok(text) => serde_json::from_str(&text).map_err(|e| e.to_string()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(HashMap::new()),
        Err(e) => Err(e.to_string()),
    }
}

fn write_dev<R: Runtime>(app: &AppHandle<R>, secrets: &HashMap<String, String>) -> Result<(), String> {
    let path = dev_file(app)?;
    fs::write(&path, serde_json::to_string(secrets).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub fn get<R: Runtime>(app: &AppHandle<R>, key: &str) -> Result<Option<String>, String> {
    match app.state::<SecretStore<R>>().get(KeyArgs { key: key.into() }) {
        Ok(result) => Ok(result.value),
        Err(StoreError::Unsupported) => Ok(read_dev(app)?.remove(key)),
        Err(e) => Err(e.to_string()),
    }
}

pub fn set<R: Runtime>(app: &AppHandle<R>, key: &str, value: &str) -> Result<(), String> {
    match app.state::<SecretStore<R>>().set(SetArgs { key: key.into(), value: value.into() }) {
        Ok(()) => Ok(()),
        Err(StoreError::Unsupported) => {
            let mut secrets = read_dev(app)?;
            secrets.insert(key.into(), value.into());
            write_dev(app, &secrets)
        }
        Err(e) => Err(e.to_string()),
    }
}

pub fn delete<R: Runtime>(app: &AppHandle<R>, key: &str) -> Result<(), String> {
    match app.state::<SecretStore<R>>().delete(KeyArgs { key: key.into() }) {
        Ok(()) => Ok(()),
        Err(StoreError::Unsupported) => {
            let mut secrets = read_dev(app)?;
            secrets.remove(key);
            write_dev(app, &secrets)
        }
        Err(e) => Err(e.to_string()),
    }
}

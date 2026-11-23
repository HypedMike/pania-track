//! Keystore-backed secret storage.
//!
//! On Android each secret is encrypted with an AES-256-GCM key that lives in the Android
//! Keystore (hardware-backed where available, never exportable) and only the ciphertext is
//! persisted. Other platforms report `Unsupported`; the frontend then falls back to a
//! development-only store, since desktop builds exist only for development.

use serde::{Deserialize, Serialize};
use tauri::{
    plugin::{Builder, TauriPlugin},
    AppHandle, Manager, Runtime,
};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("Secure storage is not supported on this platform.")]
    Unsupported,
    #[cfg(target_os = "android")]
    #[error(transparent)]
    PluginInvoke(#[from] tauri::plugin::mobile::PluginInvokeError),
}

impl Serialize for Error {
    fn serialize<S: serde::Serializer>(&self, s: S) -> std::result::Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyArgs {
    pub key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SetArgs {
    pub key: String,
    pub value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SecretResult {
    /// `None` when nothing is stored under the key, or it can no longer be decrypted.
    pub value: Option<String>,
}

#[cfg(target_os = "android")]
mod platform {
    use super::*;
    use tauri::plugin::{PluginApi, PluginHandle};

    pub struct SecretStore<R: Runtime>(PluginHandle<R>);

    pub fn init<R: Runtime, C: serde::de::DeserializeOwned>(
        _app: &AppHandle<R>,
        api: PluginApi<R, C>,
    ) -> Result<SecretStore<R>> {
        Ok(SecretStore(
            api.register_android_plugin("app.pania.secretstore", "SecretStorePlugin")?,
        ))
    }

    impl<R: Runtime> SecretStore<R> {
        pub fn get(&self, args: KeyArgs) -> Result<SecretResult> {
            Ok(self.0.run_mobile_plugin("getSecret", args)?)
        }
        pub fn set(&self, args: SetArgs) -> Result<()> {
            Ok(self.0.run_mobile_plugin("setSecret", args)?)
        }
        pub fn delete(&self, args: KeyArgs) -> Result<()> {
            Ok(self.0.run_mobile_plugin("deleteSecret", args)?)
        }
    }
}

#[cfg(not(target_os = "android"))]
mod platform {
    use super::*;
    use std::marker::PhantomData;
    use tauri::plugin::PluginApi;

    pub struct SecretStore<R: Runtime>(PhantomData<fn() -> R>);

    pub fn init<R: Runtime, C: serde::de::DeserializeOwned>(
        _app: &AppHandle<R>,
        _api: PluginApi<R, C>,
    ) -> Result<SecretStore<R>> {
        Ok(SecretStore(PhantomData))
    }

    impl<R: Runtime> SecretStore<R> {
        pub fn get(&self, _args: KeyArgs) -> Result<SecretResult> {
            Err(Error::Unsupported)
        }
        pub fn set(&self, _args: SetArgs) -> Result<()> {
            Err(Error::Unsupported)
        }
        pub fn delete(&self, _args: KeyArgs) -> Result<()> {
            Err(Error::Unsupported)
        }
    }
}

pub use platform::SecretStore;

mod commands {
    use super::*;

    #[tauri::command]
    pub async fn get_secret<R: Runtime>(app: AppHandle<R>, key: String) -> Result<SecretResult> {
        app.state::<SecretStore<R>>().get(KeyArgs { key })
    }

    #[tauri::command]
    pub async fn set_secret<R: Runtime>(app: AppHandle<R>, key: String, value: String) -> Result<()> {
        app.state::<SecretStore<R>>().set(SetArgs { key, value })
    }

    #[tauri::command]
    pub async fn delete_secret<R: Runtime>(app: AppHandle<R>, key: String) -> Result<()> {
        app.state::<SecretStore<R>>().delete(KeyArgs { key })
    }
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("secret-store")
        .invoke_handler(tauri::generate_handler![
            commands::get_secret,
            commands::set_secret,
            commands::delete_secret
        ])
        .setup(|app, api| {
            app.manage(platform::init(app, api)?);
            Ok(())
        })
        .build()
}

//! In-app updates on Android: download a release APK and hand it to the system installer.
//!
//! Android always asks the user to confirm an install, and refuses an APK that is not signed
//! with the same key as the installed app. Other platforms report `Unsupported`; the frontend
//! then falls back to opening the download link in the browser.

mod url;

use serde::{Deserialize, Serialize};
use tauri::{
    plugin::{Builder, TauriPlugin},
    AppHandle, Manager, Runtime,
};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("In-app updates are not supported on this platform.")]
    Unsupported,
    #[error("{0}")]
    InvalidUrl(String),
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
pub struct InstallStatus {
    /// Whether the user has allowed this app to install packages ("install unknown apps").
    pub allowed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DownloadArgs {
    pub url: String,
}

#[cfg(target_os = "android")]
mod platform {
    use super::*;
    use tauri::plugin::{PluginApi, PluginHandle};

    pub struct AppInstaller<R: Runtime>(PluginHandle<R>);

    pub fn init<R: Runtime, C: serde::de::DeserializeOwned>(
        _app: &AppHandle<R>,
        api: PluginApi<R, C>,
    ) -> Result<AppInstaller<R>> {
        Ok(AppInstaller(
            api.register_android_plugin("app.pania.appinstaller", "AppInstallerPlugin")?,
        ))
    }

    impl<R: Runtime> AppInstaller<R> {
        pub fn can_install(&self) -> Result<InstallStatus> {
            Ok(self.0.run_mobile_plugin("canInstall", ())?)
        }
        pub fn open_install_settings(&self) -> Result<()> {
            Ok(self.0.run_mobile_plugin("openInstallSettings", ())?)
        }
        pub fn download_and_install(&self, args: DownloadArgs) -> Result<()> {
            Ok(self.0.run_mobile_plugin("downloadAndInstall", args)?)
        }
    }
}

#[cfg(not(target_os = "android"))]
mod platform {
    use super::*;
    use std::marker::PhantomData;
    use tauri::plugin::PluginApi;

    pub struct AppInstaller<R: Runtime>(PhantomData<fn() -> R>);

    pub fn init<R: Runtime, C: serde::de::DeserializeOwned>(
        _app: &AppHandle<R>,
        _api: PluginApi<R, C>,
    ) -> Result<AppInstaller<R>> {
        Ok(AppInstaller(PhantomData))
    }

    impl<R: Runtime> AppInstaller<R> {
        pub fn can_install(&self) -> Result<InstallStatus> {
            Err(Error::Unsupported)
        }
        pub fn open_install_settings(&self) -> Result<()> {
            Err(Error::Unsupported)
        }
        pub fn download_and_install(&self, _args: DownloadArgs) -> Result<()> {
            Err(Error::Unsupported)
        }
    }
}

pub use platform::AppInstaller;

mod commands {
    use super::*;

    #[tauri::command]
    pub async fn can_install<R: Runtime>(app: AppHandle<R>) -> Result<InstallStatus> {
        app.state::<AppInstaller<R>>().can_install()
    }

    /// Opens the system screen where the user allows this app to install packages.
    #[tauri::command]
    pub async fn open_install_settings<R: Runtime>(app: AppHandle<R>) -> Result<()> {
        app.state::<AppInstaller<R>>().open_install_settings()
    }

    /// Downloads a release APK and opens the system installer on it. The address is checked
    /// here first; the native side never sees one that is not a release asset of this project.
    #[tauri::command]
    pub async fn download_and_install<R: Runtime>(app: AppHandle<R>, url: String) -> Result<()> {
        super::url::validate_download_url(&url).map_err(Error::InvalidUrl)?;
        app.state::<AppInstaller<R>>().download_and_install(DownloadArgs { url })
    }
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("app-installer")
        .invoke_handler(tauri::generate_handler![
            commands::can_install,
            commands::open_install_settings,
            commands::download_and_install
        ])
        .setup(|app, api| {
            app.manage(platform::init(app, api)?);
            Ok(())
        })
        .build()
}

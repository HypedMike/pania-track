//! In-app updates on Android: download a release APK and hand it to the system installer.
//!
//! The download itself happens here, in Rust, with progress reported to the webview; the
//! Android-only parts (the install permission, the installer screen) are in Kotlin. Android
//! always asks the user to confirm an install, and refuses an APK that is not signed with the
//! same key as the installed app. Other platforms report `Unsupported`; the frontend then
//! falls back to opening the download link in the browser.

mod download;
mod progress;
mod url;

use serde::{Deserialize, Serialize};
use tauri::{
    ipc::Channel,
    plugin::{Builder, TauriPlugin},
    AppHandle, Manager, Runtime,
};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("In-app updates are not supported on this platform.")]
    Unsupported,
    #[error("{0}")]
    InvalidUrl(String),
    #[error("{0}")]
    Download(String),
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
pub struct UpdateDir {
    /// Absolute path of the app-private folder the installer is allowed to read APKs from.
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InstallArgs {
    pub path: String,
}

pub use progress::Progress;

/// File name of the downloaded update inside [`UpdateDir`].
const APK_NAME: &str = "pania-update.apk";

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
        pub fn update_dir(&self) -> Result<UpdateDir> {
            Ok(self.0.run_mobile_plugin("updateDir", ())?)
        }
        pub fn install(&self, args: InstallArgs) -> Result<()> {
            Ok(self.0.run_mobile_plugin("install", args)?)
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
        pub fn update_dir(&self) -> Result<UpdateDir> {
            Err(Error::Unsupported)
        }
        pub fn install(&self, _args: InstallArgs) -> Result<()> {
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

    /// Downloads a release APK, reporting progress on `on_progress`, then opens the system
    /// installer on it. The address is checked here first; nothing else is ever downloaded.
    #[tauri::command]
    pub async fn download_and_install<R: Runtime>(
        app: AppHandle<R>,
        url: String,
        on_progress: Channel<Progress>,
    ) -> Result<()> {
        super::url::validate_download_url(&url).map_err(Error::InvalidUrl)?;
        let dir = app.state::<AppInstaller<R>>().update_dir()?;
        let target = std::path::Path::new(&dir.path).join(APK_NAME);
        // Blocking network and disk work, off the async runtime's threads.
        let apk = target.clone();
        tauri::async_runtime::spawn_blocking(move || {
            super::download::download(&url, &apk, &super::download::Policy::github_releases(), |p| {
                let _ = on_progress.send(p);
            })
        })
        .await
        .map_err(|e| Error::Download(e.to_string()))?
        .map_err(Error::Download)?;
        app.state::<AppInstaller<R>>().install(InstallArgs { path: target.to_string_lossy().into_owned() })
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

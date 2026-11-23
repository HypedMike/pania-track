//! Background GPS track recording.
//!
//! On Android the points are collected by a foreground service (with a persistent
//! notification), so recording keeps going with the screen off or the app in the background.
//! The webview drains the buffered points with `take_points`. Other platforms report
//! `Unsupported`, and the frontend falls back to polling the position itself.

use serde::{Deserialize, Serialize};
use tauri::{
    plugin::{Builder, TauriPlugin},
    AppHandle, Manager, Runtime,
};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("Background recording is not supported on this platform.")]
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
pub struct StartOptions {
    /// Desired time between points, in milliseconds.
    pub interval_ms: u64,
    /// Turns on off-track alerts for a tour: a JSON document with the trail to follow, how far
    /// from it is too far, and the notification texts. The service raises the alert itself, so
    /// it works with the screen off. See `OffTrackGuard.kt` for the format.
    #[serde(default)]
    pub guard_json: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RecordedPoint {
    pub latitude: f64,
    pub longitude: f64,
    pub altitude: Option<f64>,
    pub accuracy: Option<f64>,
    /// Milliseconds since the epoch.
    pub time: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TakeResult {
    /// Points recorded since the previous call; they are removed from the native buffer.
    pub points: Vec<RecordedPoint>,
    /// Whether the recording service is running.
    pub running: bool,
    /// Last error reported by the service (e.g. location turned off), if any.
    pub error: Option<String>,
}

#[cfg(target_os = "android")]
mod platform {
    use super::*;
    use tauri::plugin::{PluginApi, PluginHandle};

    pub struct TrailRecorder<R: Runtime>(PluginHandle<R>);

    pub fn init<R: Runtime, C: serde::de::DeserializeOwned>(
        _app: &AppHandle<R>,
        api: PluginApi<R, C>,
    ) -> Result<TrailRecorder<R>> {
        Ok(TrailRecorder(
            api.register_android_plugin("app.pania.trailrecorder", "TrailRecorderPlugin")?,
        ))
    }

    impl<R: Runtime> TrailRecorder<R> {
        pub fn start(&self, options: StartOptions) -> Result<()> {
            Ok(self.0.run_mobile_plugin("start", options)?)
        }
        pub fn stop(&self) -> Result<()> {
            Ok(self.0.run_mobile_plugin("stop", ())?)
        }
        pub fn take_points(&self) -> Result<TakeResult> {
            Ok(self.0.run_mobile_plugin("takePoints", ())?)
        }
        pub fn request_permissions(&self) -> Result<serde_json::Value> {
            Ok(self
                .0
                .run_mobile_plugin("requestPermissions", serde_json::json!({ "permissions": ["notifications"] }))?)
        }
    }
}

#[cfg(not(target_os = "android"))]
mod platform {
    use super::*;
    use std::marker::PhantomData;
    use tauri::plugin::PluginApi;

    pub struct TrailRecorder<R: Runtime>(PhantomData<fn() -> R>);

    pub fn init<R: Runtime, C: serde::de::DeserializeOwned>(
        _app: &AppHandle<R>,
        _api: PluginApi<R, C>,
    ) -> Result<TrailRecorder<R>> {
        Ok(TrailRecorder(PhantomData))
    }

    impl<R: Runtime> TrailRecorder<R> {
        pub fn start(&self, _options: StartOptions) -> Result<()> {
            Err(Error::Unsupported)
        }
        pub fn stop(&self) -> Result<()> {
            Err(Error::Unsupported)
        }
        pub fn take_points(&self) -> Result<TakeResult> {
            Err(Error::Unsupported)
        }
        pub fn request_permissions(&self) -> Result<serde_json::Value> {
            Err(Error::Unsupported)
        }
    }
}

pub use platform::TrailRecorder;

mod commands {
    use super::*;

    #[tauri::command]
    pub async fn start<R: Runtime>(app: AppHandle<R>, options: StartOptions) -> Result<()> {
        app.state::<TrailRecorder<R>>().start(options)
    }

    #[tauri::command]
    pub async fn stop<R: Runtime>(app: AppHandle<R>) -> Result<()> {
        app.state::<TrailRecorder<R>>().stop()
    }

    #[tauri::command]
    pub async fn take_points<R: Runtime>(app: AppHandle<R>) -> Result<TakeResult> {
        app.state::<TrailRecorder<R>>().take_points()
    }

    /// Asks for the notification permission the service's status notification needs (Android 13+).
    #[tauri::command]
    pub async fn request_permissions<R: Runtime>(app: AppHandle<R>) -> Result<serde_json::Value> {
        app.state::<TrailRecorder<R>>().request_permissions()
    }
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("trail-recorder")
        .invoke_handler(tauri::generate_handler![
            commands::start,
            commands::stop,
            commands::take_points,
            commands::request_permissions
        ])
        .setup(|app, api| {
            app.manage(platform::init(app, api)?);
            Ok(())
        })
        .build()
}

//! In-app update download for Dart. The address is checked here first; nothing else is ever
//! downloaded. The Kotlin side then opens the installer on the file.

pub use crate::updater::progress::Progress;
use crate::updater::{APK_NAME, download, url};
use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
use std::path::Path;

/// Whether `url` is an asset of this project's GitHub releases.
#[frb(sync)]
pub fn is_release_apk_url(url: String) -> bool {
    url::validate_download_url(&url).is_ok()
}

/// Name of the downloaded update file inside the update folder.
#[frb(sync)]
pub fn update_file_name() -> String {
    APK_NAME.to_string()
}

/// Downloads the release APK at `url` into `dir` (as [`update_file_name`]), reporting progress on
/// the stream; the stream ends when the file is complete. Blocking work, run by the bridge on a
/// worker thread.
pub fn download_update(url: String, dir: String, progress: StreamSink<Progress>) -> Result<(), String> {
    url::validate_download_url(&url)?;
    let target = Path::new(&dir).join(APK_NAME);
    download::download(&url, &target, &download::Policy::github_releases(), |p| {
        let _ = progress.add(p);
    })?;
    Ok(())
}

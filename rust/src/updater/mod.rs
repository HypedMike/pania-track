//! In-app updates: download a release APK, in Rust, with progress.
//!
//! The Android-only parts (the install permission, the installer screen) are in Kotlin
//! (`AppInstaller.kt`). Android always asks the user to confirm an install, and refuses an APK
//! that is not signed with the same key as the installed app.

pub mod download;
pub mod progress;
pub mod url;

/// File name of the downloaded update inside the update folder.
pub const APK_NAME: &str = "pania-update.apk";

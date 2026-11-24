//! Start-up: tells the core where it may keep files and how to reach the Android Keystore.

use crate::secrets::{self, Keystore};
use flutter_rust_bridge::DartFnFuture;
use std::sync::Arc;

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Must be called once before anything else.
///
/// `config_dir` is the app's private folder (relay list, development secrets). When
/// `keystore_available` is true the three callbacks reach the Android Keystore; otherwise
/// secrets fall back to an unencrypted file in `config_dir`, which is for development only.
pub async fn init_core(
    config_dir: String,
    keystore_available: bool,
    secret_get: impl Fn(String) -> DartFnFuture<Option<String>> + Send + Sync + 'static,
    secret_set: impl Fn(String, String) -> DartFnFuture<String> + Send + Sync + 'static,
    secret_delete: impl Fn(String) -> DartFnFuture<()> + Send + Sync + 'static,
) {
    crate::sharing::relays::set_config_dir(&config_dir);
    let keystore = keystore_available.then(|| Keystore {
        get: Arc::new(secret_get),
        set: Arc::new(secret_set),
        delete: Arc::new(secret_delete),
    });
    secrets::configure(&config_dir, keystore);
}

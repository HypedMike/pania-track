mod database;
mod identity;
mod secrets;
mod tracks;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(
            tauri_plugin_sql::Builder::default()
                .add_migrations(database::DB_URL, database::migrations())
                .build(),
        );

    // GPS access is only available on mobile; desktop falls back to the browser API.
    #[cfg(mobile)]
    let builder = builder.plugin(tauri_plugin_geolocation::init());

    // Records tracks in an Android foreground service so recording survives the screen turning off.
    let builder = builder.plugin(tauri_plugin_trail_recorder::init());

    // Keeps the Nostr secret key encrypted with a key held in the Android Keystore.
    // Only Rust code (src/secrets) talks to it; the webview is not granted its permissions.
    let builder = builder.plugin(tauri_plugin_secret_store::init());

    builder
        .invoke_handler(tauri::generate_handler![
            tracks::simplify::simplify_track,
            identity::commands::nostr_create_identity,
            identity::commands::nostr_import_identity,
            identity::commands::nostr_identity_npub,
            identity::commands::nostr_export_secret,
            identity::commands::nostr_remove_identity,
            identity::commands::nostr_sign_event,
            identity::commands::nostr_nip44_encrypt,
            identity::commands::nostr_nip44_decrypt,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

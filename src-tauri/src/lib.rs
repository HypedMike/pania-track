use tauri_plugin_sql::{Migration, MigrationKind};

/// Connection string shared with the frontend (`src/shared/database`).
/// Resolves to `pania.db` inside the app's config directory.
const DB_URL: &str = "sqlite:pania.db";

/// Append new migrations to the end; never edit one that has shipped.
fn migrations() -> Vec<Migration> {
    vec![
        Migration {
            version: 1,
            description: "create_trails",
            sql: include_str!("../migrations/001_create_trails.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 2,
            description: "trail_source_waypoints",
            sql: include_str!("../migrations/002_trail_source_waypoints.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 3,
            description: "trail_activity",
            sql: include_str!("../migrations/003_trail_activity.sql"),
            kind: MigrationKind::Up,
        },
    ]
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(
            tauri_plugin_sql::Builder::default()
                .add_migrations(DB_URL, migrations())
                .build(),
        );

    // GPS access is only available on mobile; desktop falls back to the browser API.
    #[cfg(mobile)]
    let builder = builder.plugin(tauri_plugin_geolocation::init());

    // Records tracks in an Android foreground service so recording survives the screen turning off.
    let builder = builder.plugin(tauri_plugin_trail_recorder::init());

    // Keeps the Nostr secret key encrypted with a key held in the Android Keystore.
    let builder = builder.plugin(tauri_plugin_secret_store::init());

    builder
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

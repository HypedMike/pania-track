//! The local SQLite database: its location and schema migrations.

use tauri_plugin_sql::{Migration, MigrationKind};

/// Connection string shared with the frontend (`src/shared/database`).
/// Resolves to `pania.db` inside the app's config directory.
pub const DB_URL: &str = "sqlite:pania.db";

/// Append new migrations to the end; never edit one that has shipped.
pub fn migrations() -> Vec<Migration> {
    vec![
        Migration {
            version: 1,
            description: "create_trails",
            sql: include_str!("../../migrations/001_create_trails.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 2,
            description: "trail_source_waypoints",
            sql: include_str!("../../migrations/002_trail_source_waypoints.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 3,
            description: "trail_activity",
            sql: include_str!("../../migrations/003_trail_activity.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 4,
            description: "trail_sharing",
            sql: include_str!("../../migrations/004_trail_sharing.sql"),
            kind: MigrationKind::Up,
        },
        Migration {
            version: 5,
            description: "analysis",
            sql: include_str!("../../migrations/005_analysis.sql"),
            kind: MigrationKind::Up,
        },
    ]
}

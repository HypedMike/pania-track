//! Nostr identity: the user's key pair, event signing and encryption.
//!
//! - [`keys`]: pure Rust crypto (no Tauri), unit-tested on its own.
//! - [`commands`]: the Tauri commands the frontend calls; they read the secret key from
//!   [`crate::secrets`] and never return it, except for the backup export.

pub mod commands;
pub mod keys;

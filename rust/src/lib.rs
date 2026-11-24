//! Pania's core, in Rust. The Flutter app calls into it through `flutter_rust_bridge`; only
//! `api` is visible to Dart, everything else is plain Rust that is unit tested on its own.
//!
//! - [`analysis`]: pace, stops, climbs, GPS quality, route matching, heatmap, patterns, tour review.
//! - [`tracks`]: GPX writing/reading, track simplification, difficulty grade.
//! - [`identity`]: the Nostr key pair, event signing, NIP-44.
//! - [`sharing`]: publishing and exploring trails over Nostr, and the relay list.
//! - [`secrets`]: where secrets are kept (the Android Keystore through Dart callbacks).
//! - [`updater`]: downloading a release APK, with progress.

pub mod analysis;
pub mod api;
mod frb_generated;
pub mod identity;
pub mod secrets;
pub mod sharing;
pub mod tracks;
pub mod updater;

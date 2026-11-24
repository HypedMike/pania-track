//! What Dart can call. Each file is one feature; they only move data in and out, the work is in
//! the feature modules (`analysis`, `tracks`, `identity`, `sharing`, `updater`).

pub mod analysis;
pub mod core;
pub mod identity;
pub mod sharing;
pub mod tracks;
pub mod updater;

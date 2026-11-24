//! Sharing trails over Nostr and exploring the trails other people shared.
//!
//! - [`trail_event`]: the event format; building, parsing and filtering (pure, tested).
//! - [`geohash`]: location tags so relays can find trails near a point (pure, tested).
//! - [`relays`]: the relay list and its validation (pure, tested).
//! - [`client`]: talking to relays with `nostr-sdk`.
//!
//! `crate::api::sharing` wires these to the signing key and to Dart.

pub mod client;
pub mod geohash;
pub mod relays;
pub mod trail_event;

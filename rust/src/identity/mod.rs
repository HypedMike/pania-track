//! Nostr identity: the user's key pair, event signing and encryption. Pure Rust, unit tested on
//! its own; `crate::api::identity` wires it to the secret store and to Dart.

pub mod keys;

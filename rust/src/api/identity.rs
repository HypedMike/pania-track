//! The Nostr identity for Dart. The secret key is read from the secret store inside each call and
//! never returned, except by [`nostr_export_secret`], which exists for the backup screen.

use crate::identity::keys::{self, UnsignedEvent};
use crate::secrets;
use nostr::prelude::Keys;

const SECRET_NAME: &str = "nostr-nsec";

pub(crate) async fn load_keys() -> Result<Keys, String> {
    let nsec = secrets::get(SECRET_NAME).await?.ok_or("no identity on this device")?;
    keys::parse_secret(&nsec)
}

async fn store_keys(keys: &Keys) -> Result<String, String> {
    secrets::set(SECRET_NAME, &keys::nsec(keys)).await?;
    Ok(keys::npub(keys))
}

/// Creates a new key pair, stores the secret, and returns the `npub`.
pub async fn nostr_create_identity() -> Result<String, String> {
    store_keys(&keys::generate()).await
}

/// Stores an existing secret key (`nsec1…` or hex) and returns its `npub`.
/// A key that does not parse fails with a message starting `invalid secret key`.
pub async fn nostr_import_identity(secret: String) -> Result<String, String> {
    store_keys(&keys::parse_secret(&secret)?).await
}

/// The `npub` of the stored key, or `None` when this device has no key.
pub async fn nostr_identity_npub() -> Result<Option<String>, String> {
    match secrets::get(SECRET_NAME).await? {
        Some(nsec) => Ok(Some(keys::npub(&keys::parse_secret(&nsec)?))),
        None => Ok(None),
    }
}

/// The secret key as `nsec1…`. Only for the backup screen.
pub async fn nostr_export_secret() -> Result<Option<String>, String> {
    secrets::get(SECRET_NAME).await
}

pub async fn nostr_remove_identity() -> Result<(), String> {
    secrets::delete(SECRET_NAME).await
}

/// Signs an event with the stored key; returns the event as JSON, ready for a relay.
pub async fn nostr_sign_event(event: UnsignedEvent) -> Result<String, String> {
    keys::sign_event(&load_keys().await?, event)
}

pub async fn nostr_nip44_encrypt(peer: String, plaintext: String) -> Result<String, String> {
    keys::nip44_encrypt(&load_keys().await?, &peer, &plaintext)
}

pub async fn nostr_nip44_decrypt(peer: String, payload: String) -> Result<String, String> {
    keys::nip44_decrypt(&load_keys().await?, &peer, &payload)
}

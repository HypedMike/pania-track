//! Tauri commands for the Nostr identity. The secret key is read from the vault inside each
//! command and never returned, except by `nostr_export_secret`, which exists for the backup screen.

use crate::identity::{self, UnsignedEvent};
use crate::vault;
use nostr::Keys;
use tauri::{AppHandle, Runtime};

const SECRET_NAME: &str = "nostr-nsec";

fn load_keys<R: Runtime>(app: &AppHandle<R>) -> Result<Keys, String> {
    let nsec = vault::get(app, SECRET_NAME)?.ok_or("no identity on this device")?;
    identity::parse_secret(&nsec)
}

fn store_keys<R: Runtime>(app: &AppHandle<R>, keys: &Keys) -> Result<String, String> {
    vault::set(app, SECRET_NAME, &identity::nsec(keys))?;
    Ok(identity::npub(keys))
}

/// Creates a new key pair, stores the secret, and returns the `npub`.
#[tauri::command]
pub async fn nostr_create_identity<R: Runtime>(app: AppHandle<R>) -> Result<String, String> {
    store_keys(&app, &identity::generate())
}

/// Stores an existing secret key (`nsec1…` or hex) and returns its `npub`.
/// A key that does not parse fails with a message starting `invalid secret key`.
#[tauri::command]
pub async fn nostr_import_identity<R: Runtime>(app: AppHandle<R>, secret: String) -> Result<String, String> {
    store_keys(&app, &identity::parse_secret(&secret)?)
}

/// The `npub` of the stored key, or `None` when this device has no key.
#[tauri::command]
pub async fn nostr_identity_npub<R: Runtime>(app: AppHandle<R>) -> Result<Option<String>, String> {
    match vault::get(&app, SECRET_NAME)? {
        Some(nsec) => Ok(Some(identity::npub(&identity::parse_secret(&nsec)?))),
        None => Ok(None),
    }
}

/// The secret key as `nsec1…`. Only for the backup screen.
#[tauri::command]
pub async fn nostr_export_secret<R: Runtime>(app: AppHandle<R>) -> Result<Option<String>, String> {
    vault::get(&app, SECRET_NAME)
}

#[tauri::command]
pub async fn nostr_remove_identity<R: Runtime>(app: AppHandle<R>) -> Result<(), String> {
    vault::delete(&app, SECRET_NAME)
}

/// Signs an event with the stored key; returns the event as JSON, ready for a relay.
#[tauri::command]
pub async fn nostr_sign_event<R: Runtime>(app: AppHandle<R>, event: UnsignedEvent) -> Result<String, String> {
    identity::sign_event(&load_keys(&app)?, event)
}

#[tauri::command]
pub async fn nostr_nip44_encrypt<R: Runtime>(app: AppHandle<R>, peer: String, plaintext: String) -> Result<String, String> {
    identity::nip44_encrypt(&load_keys(&app)?, &peer, &plaintext)
}

#[tauri::command]
pub async fn nostr_nip44_decrypt<R: Runtime>(app: AppHandle<R>, peer: String, payload: String) -> Result<String, String> {
    identity::nip44_decrypt(&load_keys(&app)?, &peer, &payload)
}

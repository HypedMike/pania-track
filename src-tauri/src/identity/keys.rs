//! Nostr identity: key generation, `npub`/`nsec` encoding, event signing and NIP-44 encryption.
//!
//! All of it lives here, in Rust, so the secret key never has to enter the webview except when
//! the user explicitly asks to see it for a backup. This module is plain Rust (no Tauri) so it
//! can be tested on its own; `commands.rs` wires it to the app.

use nostr::nips::nip44;
use nostr::prelude::*;
use serde::Deserialize;

/// What the frontend sends to be signed. `createdAt` (seconds) defaults to now.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UnsignedEvent {
    pub kind: u16,
    pub content: String,
    #[serde(default)]
    pub tags: Vec<Vec<String>>,
    pub created_at: Option<u64>,
}

pub fn generate() -> Keys {
    Keys::generate()
}

/// Accepts `nsec1…` or 64 hex characters.
pub fn parse_secret(input: &str) -> Result<Keys, String> {
    let secret = SecretKey::parse(input.trim()).map_err(|e| format!("invalid secret key: {e}"))?;
    Ok(Keys::new(secret))
}

pub fn npub(keys: &Keys) -> String {
    keys.public_key().to_bech32().expect("bech32 encoding of a public key cannot fail")
}

pub fn nsec(keys: &Keys) -> String {
    keys.secret_key().to_bech32().expect("bech32 encoding of a secret key cannot fail")
}

/// Signs an event and returns it as the JSON object relays expect
/// (`id`, `pubkey`, `created_at`, `kind`, `tags`, `content`, `sig`).
pub fn sign_event(keys: &Keys, event: UnsignedEvent) -> Result<String, String> {
    let tags = event
        .tags
        .into_iter()
        .map(|t| Tag::parse(t).map_err(|e| format!("invalid tag: {e}")))
        .collect::<Result<Vec<_>, _>>()?;
    let mut builder = EventBuilder::new(Kind::from(event.kind), event.content).tags(tags);
    if let Some(seconds) = event.created_at {
        builder = builder.custom_created_at(Timestamp::from_secs(seconds));
    }
    let signed = builder.finalize(keys).map_err(|e| format!("could not sign: {e}"))?;
    Ok(signed.as_json())
}

fn parse_public_key(input: &str) -> Result<PublicKey, String> {
    PublicKey::parse(input.trim()).map_err(|e| format!("invalid public key: {e}"))
}

/// NIP-44 (v2) encryption of `plaintext` for `peer` (`npub1…` or hex).
pub fn nip44_encrypt(keys: &Keys, peer: &str, plaintext: &str) -> Result<String, String> {
    nip44::encrypt(keys.secret_key(), &parse_public_key(peer)?, plaintext, nip44::Version::V2)
        .map_err(|e| format!("could not encrypt: {e}"))
}

/// NIP-44 decryption of a payload sent by `peer`.
pub fn nip44_decrypt(keys: &Keys, peer: &str, payload: &str) -> Result<String, String> {
    nip44::decrypt(keys.secret_key(), &parse_public_key(peer)?, payload)
        .map_err(|e| format!("could not decrypt: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_round_trip_through_nsec_and_hex() {
        let keys = generate();
        assert!(npub(&keys).starts_with("npub1") && nsec(&keys).starts_with("nsec1"));
        assert_eq!(npub(&parse_secret(&nsec(&keys)).unwrap()), npub(&keys));
        assert_eq!(npub(&parse_secret(&keys.secret_key().to_secret_hex()).unwrap()), npub(&keys));
    }

    #[test]
    fn rejects_things_that_are_not_secret_keys() {
        let keys = generate();
        for bad in ["", "nsec1abc", &npub(&keys), &"zz".repeat(32)] {
            assert!(parse_secret(bad).is_err(), "{bad:?} must be rejected");
        }
    }

    /// The NIP-19 example key. The public key and both bech32 strings were also derived with an
    /// independent pure-Python secp256k1 + bech32 implementation, not just by this crate.
    #[test]
    fn matches_an_independently_derived_vector() {
        let keys = parse_secret("67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa").unwrap();
        assert_eq!(keys.public_key().to_hex(), "7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e");
        assert_eq!(npub(&keys), "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg");
        assert_eq!(nsec(&keys), "nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5");
    }

    #[test]
    fn signed_events_verify_and_carry_tags() {
        let keys = generate();
        let json = sign_event(
            &keys,
            UnsignedEvent {
                kind: 30023,
                content: "<gpx/>".into(),
                tags: vec![vec!["d".into(), "trail-1".into()], vec!["error_max_m".into(), "3.9".into()]],
                created_at: Some(1_700_000_000),
            },
        )
        .unwrap();
        let event = Event::from_json(&json).unwrap();
        event.verify().expect("signature must verify");
        assert_eq!(event.pubkey, keys.public_key());
        assert_eq!(event.kind.as_u16(), 30023);
        assert_eq!(event.created_at.as_secs(), 1_700_000_000);
        assert_eq!(event.tags.len(), 2);
    }

    #[test]
    fn a_tampered_event_fails_verification() {
        let keys = generate();
        let json = sign_event(&keys, UnsignedEvent { kind: 1, content: "a".into(), tags: vec![], created_at: None }).unwrap();
        let tampered = json.replace("\"content\":\"a\"", "\"content\":\"b\"");
        assert!(Event::from_json(&tampered).unwrap().verify().is_err());
    }

    #[test]
    fn nip44_round_trips_between_two_identities_and_not_for_a_third() {
        let (alice, bob, eve) = (generate(), generate(), generate());
        let payload = nip44_encrypt(&alice, &npub(&bob), "hello — trail 🥾").unwrap();
        assert_eq!(nip44_decrypt(&bob, &npub(&alice), &payload).unwrap(), "hello — trail 🥾");
        assert!(nip44_decrypt(&eve, &npub(&alice), &payload).is_err());
    }

    #[test]
    fn invalid_tags_are_reported_not_ignored() {
        let keys = generate();
        let bad = UnsignedEvent { kind: 1, content: String::new(), tags: vec![vec![]], created_at: None };
        assert!(sign_event(&keys, bad).is_err());
    }
}

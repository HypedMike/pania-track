//! The list of relays the app talks to: sensible defaults plus the user's own.
//!
//! Stored as a small JSON file (a list of `wss://` URLs). Only secure websockets are accepted,
//! because a trail shared over `ws://` could be read or altered on the way.

use nostr::prelude::RelayUrl;
use std::{fs, path::Path};

/// Public relays to start with. Not vetted for availability: check them before a release, and
/// expect the list to need updating over time.
pub const DEFAULT_RELAYS: [&str; 6] = [
    "wss://relay.damus.io",
    "wss://nos.lol",
    "wss://relay.primal.net",
    "wss://relay.nostr.band",
    "wss://offchain.pub",
    "wss://relay.snort.social",
];

const MAX_RELAYS: usize = 30;

static CONFIG_DIR: std::sync::OnceLock<std::sync::Mutex<std::path::PathBuf>> = std::sync::OnceLock::new();

/// Where `relays.json` lives; set once at start-up.
pub fn set_config_dir(dir: &str) {
    let cell = CONFIG_DIR.get_or_init(|| std::sync::Mutex::new(std::path::PathBuf::new()));
    *cell.lock().unwrap() = std::path::PathBuf::from(dir);
}

fn relays_file() -> std::path::PathBuf {
    let dir = CONFIG_DIR.get().map(|d| d.lock().unwrap().clone()).unwrap_or_default();
    dir.join("relays.json")
}

/// The relay list the app uses now: the saved one, or the defaults.
pub fn current() -> Vec<String> {
    load(&relays_file())
}

pub fn save_current(relays: &[String]) -> Result<(), String> {
    save(&relays_file(), relays)
}

pub fn defaults() -> Vec<String> {
    DEFAULT_RELAYS.iter().map(|s| s.to_string()).collect()
}

/// Validates and normalizes a relay address (`wss://` only, no trailing slash).
pub fn normalize(input: &str) -> Result<String, String> {
    let text = input.trim();
    if text.is_empty() || text.len() > 200 || text.chars().any(|c| c.is_whitespace() || c.is_control()) {
        return Err("invalid relay address".into());
    }
    if !text.to_ascii_lowercase().starts_with("wss://") {
        return Err("relay addresses must start with wss://".into());
    }
    let url = RelayUrl::parse(text).map_err(|_| "invalid relay address".to_string())?;
    Ok(url.to_string().trim_end_matches('/').to_string())
}

/// The saved list, or the defaults when there is none (or it is unreadable or empty).
pub fn load(path: &Path) -> Vec<String> {
    let saved: Option<Vec<String>> = fs::read_to_string(path).ok().and_then(|t| serde_json::from_str(&t).ok());
    match saved {
        Some(list) if !list.is_empty() => list,
        _ => defaults(),
    }
}

pub fn save(path: &Path, relays: &[String]) -> Result<(), String> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    fs::write(path, serde_json::to_string(relays).map_err(|e| e.to_string())?).map_err(|e| e.to_string())
}

pub fn add(relays: &mut Vec<String>, input: &str) -> Result<(), String> {
    let url = normalize(input)?;
    if relays.iter().any(|r| r.eq_ignore_ascii_case(&url)) {
        return Err("that relay is already in the list".into());
    }
    if relays.len() >= MAX_RELAYS {
        return Err(format!("at most {MAX_RELAYS} relays"));
    }
    relays.push(url);
    Ok(())
}

pub fn remove(relays: &mut Vec<String>, input: &str) -> Result<(), String> {
    let url = normalize(input).unwrap_or_else(|_| input.trim().to_string());
    if relays.len() <= 1 {
        return Err("keep at least one relay".into());
    }
    let before = relays.len();
    relays.retain(|r| !r.eq_ignore_ascii_case(&url));
    if relays.len() == before {
        return Err("that relay is not in the list".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn there_are_at_least_five_valid_unique_defaults() {
        let d = defaults();
        assert!(d.len() >= 5);
        for r in &d {
            assert_eq!(&normalize(r).unwrap(), r);
        }
        let mut sorted = d.clone();
        sorted.sort();
        sorted.dedup();
        assert_eq!(sorted.len(), d.len());
    }

    #[test]
    fn only_secure_websocket_addresses_are_accepted_and_normalized() {
        assert_eq!(normalize("  WSS://Relay.Example.com/  ").unwrap(), "wss://relay.example.com");
        for bad in ["", "ws://relay.example.com", "https://relay.example.com", "relay.example.com", "wss://", "wss://a b.com", "wss://x.com/a\nb"] {
            assert!(normalize(bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn adding_removing_and_persisting() {
        let dir = std::env::temp_dir().join(format!("pania-relays-{}", std::process::id()));
        let path = dir.join("relays.json");
        assert_eq!(load(&path), defaults(), "no file yet: defaults");
        let mut list = defaults();
        add(&mut list, "wss://my.relay.example").unwrap();
        assert!(add(&mut list, "wss://MY.relay.example/").is_err(), "duplicate");
        save(&path, &list).unwrap();
        assert_eq!(load(&path), list);
        remove(&mut list, "wss://my.relay.example/").unwrap();
        assert_eq!(list, defaults());
        assert!(remove(&mut list, "wss://nope.example").is_err());
        let mut one = vec!["wss://only.example".to_string()];
        assert!(remove(&mut one, "wss://only.example").is_err(), "never empty");
        fs::write(&path, "garbage").unwrap();
        assert_eq!(load(&path), defaults(), "corrupt file: defaults");
        let _ = fs::remove_dir_all(&dir);
    }
}

//! Sharing and exploring trails, and the relay list, for Dart.

use super::identity::load_keys;
use crate::identity::keys::{self, UnsignedEvent};
use crate::sharing::{
    client::{self, Outcome},
    relays,
    trail_event::{self, Fidelity, ShareInput},
};
use crate::tracks::{difficulty::Difficulty, simplify::Report};
use nostr::prelude::Event;
use std::time::Duration;

pub use crate::sharing::trail_event::{ExploreQuery, SharedTrail};

const FETCH_TIMEOUT: Duration = Duration::from_secs(8);

pub fn relays_list() -> Vec<String> {
    relays::current()
}

pub fn relays_add(url: String) -> Result<Vec<String>, String> {
    let mut list = relays::current();
    relays::add(&mut list, &url)?;
    relays::save_current(&list)?;
    Ok(list)
}

pub fn relays_remove(url: String) -> Result<Vec<String>, String> {
    let mut list = relays::current();
    relays::remove(&mut list, &url)?;
    relays::save_current(&list)?;
    Ok(list)
}

pub fn relays_reset() -> Result<Vec<String>, String> {
    let list = relays::defaults();
    relays::save_current(&list)?;
    Ok(list)
}

#[derive(Debug)]
pub struct ShareResult {
    pub event_id: String,
    pub d_tag: String,
    pub report: Report,
    pub difficulty: Difficulty,
    pub content_bytes: usize,
    pub relays_ok: Vec<String>,
    pub relays_failed: Vec<(String, String)>,
}

fn publish_outcome(outcome: &Outcome) -> Result<(), String> {
    if outcome.ok.is_empty() {
        let why = outcome.failed.first().map(|(r, e)| format!(" ({r}: {e})")).unwrap_or_default();
        return Err(format!("no relay accepted the event{why}"));
    }
    Ok(())
}

async fn sign(keys: &nostr::prelude::Keys, unsigned: UnsignedEvent) -> Result<Event, String> {
    Event::from_json(keys::sign_event(keys, unsigned)?).map_err(|e| e.to_string())
}

/// Simplifies a trail, signs it with the user's key and publishes it to the relays.
pub async fn share_trail(trail: ShareInput) -> Result<ShareResult, String> {
    let keys = load_keys().await?;
    let prepared = trail_event::build(&trail, None)?;
    let event = sign(&keys, prepared.event).await?;
    let outcome = client::publish(&relays::current(), &event).await?;
    publish_outcome(&outcome)?;
    Ok(ShareResult {
        event_id: event.id.to_hex(),
        d_tag: trail.id.trim().to_string(),
        report: prepared.report,
        difficulty: prepared.difficulty,
        content_bytes: prepared.content_bytes,
        relays_ok: outcome.ok,
        relays_failed: outcome.failed,
    })
}

/// Asks relays to delete a shared trail (NIP-09). Relays may keep copies; this is a request.
pub async fn unshare_trail(trail_id: String) -> Result<Vec<String>, String> {
    let keys = load_keys().await?;
    let unsigned = trail_event::deletion(&keys.public_key(), &trail_id, None);
    let event = sign(&keys, unsigned).await?;
    let outcome = client::publish(&relays::current(), &event).await?;
    publish_outcome(&outcome)?;
    Ok(outcome.ok)
}

/// Shared trails near a point, filtered and ordered by closeness.
pub async fn explore_trails(query: ExploreQuery) -> Result<Vec<SharedTrail>, String> {
    query.validate()?;
    let events = client::fetch(&relays::current(), trail_event::relay_filter(&query), FETCH_TIMEOUT).await?;
    Ok(trail_event::select(events, &query))
}

// Re-exported so the generated Dart code has the type in reach.
#[allow(dead_code)]
type _Fidelity = Fidelity;

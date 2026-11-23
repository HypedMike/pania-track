//! Tauri commands for sharing and exploring trails, and for the relay list.

use super::client::{self, Outcome};
use super::relays;
use super::trail_event::{self, ExploreQuery, ShareInput, SharedTrail};
use crate::identity::{commands::load_keys, keys};
use crate::tracks::difficulty::Difficulty;
use crate::tracks::simplify::Report;
use nostr::prelude::Event;
use serde::Serialize;
use std::{path::PathBuf, time::Duration};
use tauri::{AppHandle, Manager, Runtime};

const FETCH_TIMEOUT: Duration = Duration::from_secs(8);

fn relays_file<R: Runtime>(app: &AppHandle<R>) -> Result<PathBuf, String> {
    Ok(app.path().app_config_dir().map_err(|e| e.to_string())?.join("relays.json"))
}

fn current_relays<R: Runtime>(app: &AppHandle<R>) -> Result<Vec<String>, String> {
    Ok(relays::load(&relays_file(app)?))
}

#[tauri::command]
pub async fn relays_list<R: Runtime>(app: AppHandle<R>) -> Result<Vec<String>, String> {
    current_relays(&app)
}

#[tauri::command]
pub async fn relays_add<R: Runtime>(app: AppHandle<R>, url: String) -> Result<Vec<String>, String> {
    let mut list = current_relays(&app)?;
    relays::add(&mut list, &url)?;
    relays::save(&relays_file(&app)?, &list)?;
    Ok(list)
}

#[tauri::command]
pub async fn relays_remove<R: Runtime>(app: AppHandle<R>, url: String) -> Result<Vec<String>, String> {
    let mut list = current_relays(&app)?;
    relays::remove(&mut list, &url)?;
    relays::save(&relays_file(&app)?, &list)?;
    Ok(list)
}

#[tauri::command]
pub async fn relays_reset<R: Runtime>(app: AppHandle<R>) -> Result<Vec<String>, String> {
    let list = relays::defaults();
    relays::save(&relays_file(&app)?, &list)?;
    Ok(list)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
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

/// Simplifies a trail, signs it with the user's key and publishes it to the relays.
#[tauri::command]
pub async fn share_trail<R: Runtime>(app: AppHandle<R>, trail: ShareInput) -> Result<ShareResult, String> {
    let keys = load_keys(&app)?;
    let prepared = trail_event::build(&trail, None)?;
    let event = Event::from_json(keys::sign_event(&keys, prepared.event)?).map_err(|e| e.to_string())?;
    let outcome = client::publish(&current_relays(&app)?, &event).await?;
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
#[tauri::command]
pub async fn unshare_trail<R: Runtime>(app: AppHandle<R>, trail_id: String) -> Result<Vec<String>, String> {
    let keys = load_keys(&app)?;
    let unsigned = trail_event::deletion(&keys.public_key(), &trail_id, None);
    let event = Event::from_json(keys::sign_event(&keys, unsigned)?).map_err(|e| e.to_string())?;
    let outcome = client::publish(&current_relays(&app)?, &event).await?;
    publish_outcome(&outcome)?;
    Ok(outcome.ok)
}

/// Shared trails near a point, filtered and ordered by closeness.
#[tauri::command]
pub async fn explore_trails<R: Runtime>(app: AppHandle<R>, query: ExploreQuery) -> Result<Vec<SharedTrail>, String> {
    query.validate()?;
    let events = client::fetch(&current_relays(&app)?, trail_event::relay_filter(&query), FETCH_TIMEOUT).await?;
    Ok(trail_event::select(events, &query))
}

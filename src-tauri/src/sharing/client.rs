//! Talking to relays. Each operation connects, does its work and disconnects: the app only
//! needs a relay when the user shares or explores, so no connection is kept open.

use nostr_sdk::prelude::*;
use std::time::Duration;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(6);

/// Which relays accepted an event and which did not (with the reason they gave).
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct Outcome {
    pub ok: Vec<String>,
    pub failed: Vec<(String, String)>,
}

async fn connect(relays: &[String]) -> Result<Client, String> {
    if relays.is_empty() {
        return Err("no relays configured".into());
    }
    let client = Client::default();
    for relay in relays {
        client.add_relay(relay.as_str()).await.map_err(|e| format!("{relay}: {e}"))?;
    }
    client.connect().and_wait(CONNECT_TIMEOUT).await;
    // Without this, an offline phone would look like "no trails nearby".
    let connected = client.relays().await.values().filter(|r| r.status() == RelayStatus::Connected).count();
    if connected == 0 {
        client.shutdown().await;
        return Err("could not connect to any relay; check your connection or the relay list".into());
    }
    Ok(client)
}

/// Sends an already signed event to every relay.
pub async fn publish(relays: &[String], event: &Event) -> Result<Outcome, String> {
    let client = connect(relays).await?;
    let result = client.send_event(event).await;
    client.shutdown().await;
    let output = result.map_err(|e| e.to_string())?;
    Ok(Outcome {
        ok: output.success.keys().map(|r| r.to_string()).collect(),
        failed: output.failed.iter().map(|(r, why)| (r.to_string(), why.to_string())).collect(),
    })
}

/// Fetches the events matching `filter` from every relay (merged, duplicates removed).
pub async fn fetch(relays: &[String], filter: Filter, timeout: Duration) -> Result<Vec<Event>, String> {
    let client = connect(relays).await?;
    let result = client.fetch_events(filter).timeout(timeout).await;
    client.shutdown().await;
    Ok(result.map_err(|e| e.to_string())?.into_iter().collect())
}

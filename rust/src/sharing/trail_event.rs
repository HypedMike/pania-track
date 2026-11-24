//! The Nostr event that carries a shared trail: building one to publish, and reading (and
//! distrusting) the ones other people published.
//!
//! The event is addressable ([`TRAIL_KIND`], `d` = the trail's id), so sharing a trail again
//! replaces the earlier version. `content` is the simplified track as GPX, without timestamps.
//! Tags carry what a client needs to list and filter trails without opening the GPX.
//!
//! Anything read from the network is untrusted: the signature is verified, and the numbers used
//! for filtering (distance, climb, difficulty) are recomputed from the track itself instead of
//! taken from the author's tags. Only the fidelity figures are the author's own claims.

use super::geohash;
use crate::identity::keys::UnsignedEvent;
use crate::tracks::difficulty::{self, Activity, Difficulty};
use crate::tracks::gpx::{self, Waypoint};
use crate::tracks::simplify::{self, Options, Point, Report};
use nostr::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Addressable event kind (NIP-01: 30000–39999) for a shared trail. Provisional: it is not in
/// the NIPs kinds table as of writing, but that table is not exhaustive, so check the kinds
/// registry before relying on it.
pub const TRAIL_KIND: u16 = 30427;
/// Relays commonly limit event size; stay well under typical limits (unverified, tune later).
pub const MAX_CONTENT_BYTES: usize = 100_000;
const MAX_TOLERANCE_M: f64 = 32.0;
const MAX_NAME_CHARS: usize = 100;
const MAX_DESCRIPTION_CHARS: usize = 2_000;
const MAX_RESULTS: usize = 100;
/// Longest track accepted for sharing. Simplification is quadratic on pathological input, so
/// this bounds the work; a real track of this size takes a fraction of a second.
const MAX_INPUT_POINTS: usize = 200_000;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ShareInput {
    /// The trail's local id; becomes the event's `d` tag.
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    pub activity: Activity,
    pub coordinates: Vec<Point>,
    #[serde(default)]
    pub waypoints: Vec<Waypoint>,
    /// The sharer's display name, published as the `author` tag.
    #[serde(default)]
    pub author_name: Option<String>,
}

#[derive(Debug)]
pub struct Prepared {
    pub event: UnsignedEvent,
    pub report: Report,
    pub difficulty: Difficulty,
    pub content_bytes: usize,
}

fn clip(text: &str, max: usize) -> String {
    text.trim().chars().filter(|c| !c.is_control() || *c == '\n').take(max).collect()
}

fn report_tags(r: &Report) -> Vec<Vec<String>> {
    let tag = |k: &str, v: String| vec![k.to_string(), v];
    let mut tags = vec![
        tag("original_points", r.original_points.to_string()),
        tag("points", r.kept_points.to_string()),
        tag("removed_pct", r.removed_pct.to_string()),
        tag("tolerance_m", r.tolerance_m.to_string()),
        tag("error_max_m", r.max_error_m.to_string()),
        tag("error_p95_m", r.p95_error_m.to_string()),
        tag("error_mean_m", r.mean_error_m.to_string()),
        tag("distance_m", r.original_distance_m.to_string()),
        tag("simplified_distance_m", r.simplified_distance_m.to_string()),
    ];
    if let (Some(g), Some(sg)) = (r.original_gain_m, r.simplified_gain_m) {
        tags.push(tag("gain_m", g.to_string()));
        tags.push(tag("simplified_gain_m", sg.to_string()));
    }
    if let Some(a) = r.max_altitude_error_m {
        tags.push(tag("error_alt_max_m", a.to_string()));
    }
    tags
}

/// Simplifies the track, writes the GPX and assembles the unsigned event. If the GPX is too big
/// for relays the tolerance is doubled (up to [`MAX_TOLERANCE_M`]) until it fits.
pub fn build(input: &ShareInput, created_at: Option<u64>) -> Result<Prepared, String> {
    build_with_limit(input, created_at, MAX_CONTENT_BYTES)
}

fn build_with_limit(input: &ShareInput, created_at: Option<u64>, max_bytes: usize) -> Result<Prepared, String> {
    if input.coordinates.len() > MAX_INPUT_POINTS {
        return Err("this trail has too many points to share".into());
    }
    let id = input.id.trim();
    if id.is_empty() || id.chars().count() > 64 || id.chars().any(char::is_control) {
        return Err("invalid trail id".into());
    }
    let name = clip(&input.name, MAX_NAME_CHARS);
    if name.is_empty() {
        return Err("a shared trail needs a name".into());
    }
    let description = clip(&input.description, MAX_DESCRIPTION_CHARS);

    let mut tolerance = Options::default().tolerance_m;
    loop {
        let options = Options { tolerance_m: tolerance, altitude_tolerance_m: tolerance, ..Options::default() };
        let simplified = simplify::simplify_with_report(&input.coordinates, options);
        if simplified.kept.len() < 2 {
            return Err("a trail needs at least two valid points to be shared".into());
        }
        let points: Vec<Point> = simplified.kept.iter().map(|&i| input.coordinates[i].clone()).collect();
        let content = gpx::write_gpx(&name, &description, &points, &input.waypoints);
        if content.len() > max_bytes {
            if tolerance >= MAX_TOLERANCE_M {
                return Err("this trail is too large to share".into());
            }
            tolerance *= 2.0;
            continue;
        }

        let report = simplified.report;
        let difficulty = difficulty::assess(input.activity, report.original_distance_m, report.original_gain_m);
        let mut tags = vec![
            vec!["d".to_string(), id.to_string()],
            vec!["title".into(), name],
            vec!["t".into(), input.activity.as_str().into()],
            vec!["difficulty".into(), difficulty.as_str().into()],
            vec!["client".into(), "pania".into()],
        ];
        if !description.is_empty() {
            tags.push(vec!["summary".into(), description]);
        }
        if let Some(author) = input.author_name.as_deref().map(|n| clip(n, MAX_NAME_CHARS)).filter(|n| !n.is_empty()) {
            tags.push(vec!["author".into(), author]);
        }
        for cell in geohash::ladder(points[0].latitude, points[0].longitude) {
            tags.push(vec!["g".into(), cell]);
        }
        tags.extend(report_tags(&report));

        let content_bytes = content.len();
        return Ok(Prepared {
            event: UnsignedEvent { kind: TRAIL_KIND, content, tags, created_at },
            report,
            difficulty,
            content_bytes,
        });
    }
}

/// NIP-09 deletion request for a previously shared trail. Relays may or may not honour it.
pub fn deletion(pubkey: &PublicKey, trail_id: &str, created_at: Option<u64>) -> UnsignedEvent {
    UnsignedEvent {
        kind: 5,
        content: "removed by author".into(),
        tags: vec![
            vec!["a".into(), format!("{TRAIL_KIND}:{}:{}", pubkey.to_hex(), trail_id.trim())],
            vec!["k".into(), TRAIL_KIND.to_string()],
        ],
        created_at,
    }
}

/// The author's own account of how faithful the published line is. Not verified.
#[derive(Debug, Clone, Default, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Fidelity {
    pub original_points: Option<f64>,
    pub points: Option<f64>,
    pub removed_pct: Option<f64>,
    pub tolerance_m: Option<f64>,
    pub max_error_m: Option<f64>,
    pub p95_error_m: Option<f64>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SharedTrail {
    pub event_id: String,
    /// Author's public key, hex and `npub1…`.
    pub author_pubkey: String,
    pub author_npub: String,
    pub author_name: Option<String>,
    /// The `d` tag: identifies the trail among its author's trails.
    pub d_tag: String,
    pub name: String,
    pub description: String,
    pub activity: Activity,
    /// Recomputed from the track, not read from tags.
    pub difficulty: Difficulty,
    pub distance_m: f64,
    pub gain_m: Option<f64>,
    pub created_at: u64,
    pub coordinates: Vec<Point>,
    pub waypoints: Vec<Waypoint>,
    pub fidelity: Fidelity,
    /// Distance from the searched point to the trail's start, in km (set by [`select`]).
    pub away_km: f64,
}

fn tag_value<'a>(event: &'a Event, key: &str) -> Option<&'a str> {
    event.tags.iter().map(|t| t.as_slice()).find(|t| t.first().map(String::as_str) == Some(key)).and_then(|t| t.get(1)).map(String::as_str)
}

fn tag_number(event: &Event, key: &str) -> Option<f64> {
    tag_value(event, key)?.parse::<f64>().ok().filter(|v| v.is_finite())
}

/// Checks and decodes a shared-trail event received from a relay.
pub fn parse_event(event: &Event) -> Result<SharedTrail, String> {
    if event.kind.as_u16() != TRAIL_KIND {
        return Err("not a trail event".into());
    }
    event.verify().map_err(|e| format!("bad signature: {e}"))?;
    if event.content.len() > MAX_CONTENT_BYTES {
        return Err("event too large".into());
    }
    let d_tag = tag_value(event, "d").map(|d| clip(d, 64)).filter(|d| !d.is_empty()).ok_or("missing d tag")?;
    let parsed = gpx::parse_gpx(&event.content)?;
    if parsed.points.len() < 2 {
        return Err("track has fewer than two points".into());
    }
    let refs: Vec<&Point> = parsed.points.iter().collect();
    let distance_m = simplify::distance_m(&refs).round();
    let gain_m = simplify::gain_m(&refs).map(f64::round);
    let activity = event
        .tags
        .iter()
        .map(|t| t.as_slice())
        .filter(|t| t.first().map(String::as_str) == Some("t"))
        .filter_map(|t| t.get(1).and_then(|v| Activity::parse(v)))
        .next()
        .unwrap_or(Activity::Foot);
    let name = tag_value(event, "title").map(|n| clip(n, MAX_NAME_CHARS)).filter(|n| !n.is_empty())
        .or_else(|| parsed.name.as_deref().map(|n| clip(n, MAX_NAME_CHARS)).filter(|n| !n.is_empty()))
        .unwrap_or_else(|| "Untitled trail".into());

    Ok(SharedTrail {
        event_id: event.id.to_hex(),
        author_pubkey: event.pubkey.to_hex(),
        author_npub: event.pubkey.to_bech32().map_err(|e| e.to_string())?,
        author_name: tag_value(event, "author").map(|n| clip(n, MAX_NAME_CHARS)).filter(|n| !n.is_empty()),
        d_tag,
        name,
        description: tag_value(event, "summary").map(|d| clip(d, MAX_DESCRIPTION_CHARS)).unwrap_or_else(|| clip(parsed.description.as_deref().unwrap_or(""), MAX_DESCRIPTION_CHARS)),
        activity,
        difficulty: difficulty::assess(activity, distance_m, gain_m),
        distance_m,
        gain_m,
        created_at: event.created_at.as_secs(),
        coordinates: parsed.points,
        waypoints: parsed.waypoints,
        fidelity: Fidelity {
            original_points: tag_number(event, "original_points"),
            points: tag_number(event, "points"),
            removed_pct: tag_number(event, "removed_pct"),
            tolerance_m: tag_number(event, "tolerance_m"),
            max_error_m: tag_number(event, "error_max_m"),
            p95_error_m: tag_number(event, "error_p95_m"),
        },
        away_km: 0.0,
    })
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExploreQuery {
    pub lat: f64,
    pub lon: f64,
    /// Search radius around the point, in km (1–200).
    pub radius_km: f64,
    pub min_length_km: Option<f64>,
    pub max_length_km: Option<f64>,
    pub activity: Option<Activity>,
    /// Empty means any difficulty.
    #[serde(default)]
    pub difficulty: Vec<Difficulty>,
}

impl ExploreQuery {
    pub fn validate(&self) -> Result<(), String> {
        if !(self.lat.is_finite() && self.lon.is_finite() && self.lat.abs() <= 90.0 && self.lon.abs() <= 180.0) {
            return Err("invalid search position".into());
        }
        if !(self.radius_km.is_finite() && (1.0..=200.0).contains(&self.radius_km)) {
            return Err("search radius must be between 1 and 200 km".into());
        }
        Ok(())
    }
}

/// The filter to send to relays: trail events whose start geohash is in the cells around the
/// search point, optionally restricted to one activity.
pub fn relay_filter(q: &ExploreQuery) -> Filter {
    let mut filter = Filter::new()
        .kind(Kind::from(TRAIL_KIND))
        .custom_tags(SingleLetterTag::LOWERCASE_G, geohash::cells_around(q.lat, q.lon, q.radius_km))
        .limit(300);
    if let Some(activity) = q.activity {
        filter = filter.custom_tag(SingleLetterTag::LOWERCASE_T, activity.as_str());
    }
    filter
}

/// Parses the events, drops invalid and duplicate ones (the newest version of each
/// author+trail wins), applies the filters on real distances and orders by closeness.
pub fn select(events: Vec<Event>, q: &ExploreQuery) -> Vec<SharedTrail> {
    let mut latest: HashMap<(String, String), SharedTrail> = HashMap::new();
    for event in &events {
        let Ok(trail) = parse_event(event) else { continue };
        let key = (trail.author_pubkey.clone(), trail.d_tag.clone());
        if latest.get(&key).is_none_or(|old| trail.created_at > old.created_at) {
            latest.insert(key, trail);
        }
    }
    let center = Point { latitude: q.lat, longitude: q.lon, altitude: None };
    let mut trails: Vec<SharedTrail> = latest
        .into_values()
        .filter_map(|mut t| {
            t.away_km = simplify::haversine_m(&center, &t.coordinates[0]) / 1000.0;
            let km = t.distance_m / 1000.0;
            let keep = t.away_km <= q.radius_km
                && q.min_length_km.is_none_or(|m| km >= m)
                && q.max_length_km.is_none_or(|m| km <= m)
                && q.activity.is_none_or(|a| t.activity == a)
                && (q.difficulty.is_empty() || q.difficulty.contains(&t.difficulty));
            keep.then_some(t)
        })
        .collect();
    trails.sort_by(|a, b| a.away_km.total_cmp(&b.away_km).then_with(|| b.created_at.cmp(&a.created_at)));
    trails.truncate(MAX_RESULTS);
    trails
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::identity::keys;

    fn walk(lat0: f64, lon0: f64, n: usize, step: f64, climb_per_pt: f64) -> Vec<Point> {
        (0..n)
            .map(|i| Point {
                latitude: lat0 + i as f64 * step,
                longitude: lon0 + (i as f64 / 7.0).sin() * 0.001,
                altitude: Some(100.0 + i as f64 * climb_per_pt),
            })
            .collect()
    }

    fn input(id: &str, coords: Vec<Point>) -> ShareInput {
        ShareInput { id: id.into(), name: "Monte Serra ridge".into(), description: "a nice <ridge> & views".into(), activity: Activity::Foot, coordinates: coords, waypoints: vec![], author_name: Some("Giulia Neri".into()) }
    }

    fn publish(keys: &Keys, input: &ShareInput, at: u64) -> Event {
        let prepared = build(input, Some(at)).unwrap();
        Event::from_json(&keys::sign_event(keys, prepared.event).unwrap()).unwrap()
    }

    fn query(lat: f64, lon: f64) -> ExploreQuery {
        ExploreQuery { lat, lon, radius_km: 20.0, min_length_km: None, max_length_km: None, activity: None, difficulty: vec![] }
    }

    #[test]
    fn a_built_event_round_trips_through_signing_and_parsing() {
        let keys = keys::generate();
        let coords = walk(43.7, 10.4, 2000, 5e-5, 0.4);
        let event = publish(&keys, &input("trail-1", coords.clone()), 1_700_000_000);
        let t = parse_event(&event).unwrap();
        assert_eq!((t.d_tag.as_str(), t.name.as_str(), t.author_name.as_deref()), ("trail-1", "Monte Serra ridge", Some("Giulia Neri")));
        assert_eq!(t.author_pubkey, keys.public_key().to_hex());
        assert_eq!(t.description, "a nice <ridge> & views");
        assert!(t.coordinates.len() < coords.len() / 4, "kept {}", t.coordinates.len());
        assert_eq!(t.activity, Activity::Foot);
        assert!(t.fidelity.max_error_m.unwrap() <= 6.0 && t.fidelity.removed_pct.unwrap() > 50.0);
        assert!(t.distance_m > 0.0 && t.gain_m.unwrap() > 0.0);
        // No timestamps leak into the published track.
        assert!(!event.content.contains("<time"));
        // The start geohash ladder is there, finest cell first-to-last.
        let g: Vec<&str> = event.tags.iter().map(|t| t.as_slice()).filter(|t| t[0] == "g").map(|t| t[1].as_str()).collect();
        assert_eq!(g.len(), geohash::MAX_PRECISION);
    }

    #[test]
    fn distance_and_difficulty_come_from_the_track_not_from_tags() {
        let keys = keys::generate();
        let prepared = build(&input("x", walk(43.7, 10.4, 300, 5e-5, 0.1)), Some(1)).unwrap();
        let mut unsigned = prepared.event;
        for t in unsigned.tags.iter_mut() {
            if t[0] == "distance_m" { t[1] = "999999999".into() }
            if t[0] == "difficulty" { t[1] = "hard".into() }
        }
        let event = Event::from_json(&keys::sign_event(&keys, unsigned).unwrap()).unwrap();
        let t = parse_event(&event).unwrap();
        assert!(t.distance_m < 20_000.0, "{}", t.distance_m);
        assert_eq!(t.difficulty, Difficulty::Easy);
    }

    #[test]
    fn rejects_tampered_wrong_kind_and_malformed_events() {
        let keys = keys::generate();
        let event = publish(&keys, &input("a", walk(43.7, 10.4, 50, 5e-4, 0.0)), 5);
        let tampered = event.as_json().replace("Monte Serra ridge", "Free money here");
        assert!(parse_event(&Event::from_json(&tampered).unwrap()).is_err());
        let note = Event::from_json(&keys::sign_event(&keys, UnsignedEvent { kind: 1, content: "hi".into(), tags: vec![], created_at: None }).unwrap()).unwrap();
        assert!(parse_event(&note).is_err());
        let no_d = UnsignedEvent { kind: TRAIL_KIND, content: gpx::write_gpx("n", "", &walk(1.0, 1.0, 3, 1e-3, 0.0), &[]), tags: vec![], created_at: None };
        assert!(parse_event(&Event::from_json(&keys::sign_event(&keys, no_d).unwrap()).unwrap()).is_err());
        let junk = UnsignedEvent { kind: TRAIL_KIND, content: "not gpx <<<".into(), tags: vec![vec!["d".into(), "x".into()]], created_at: None };
        assert!(parse_event(&Event::from_json(&keys::sign_event(&keys, junk).unwrap()).unwrap()).is_err());
    }

    #[test]
    fn invalid_input_is_refused_before_publishing() {
        let ok = walk(43.7, 10.4, 10, 5e-4, 0.0);
        assert!(build(&ShareInput { name: "  ".into(), ..input("a", ok.clone()) }, None).is_err());
        assert!(build(&input("", ok.clone()), None).is_err());
        assert!(build(&input("a", vec![ok[0].clone()]), None).is_err());
        assert!(build(&input("a", vec![]), None).is_err());
    }

    #[test]
    fn a_track_that_does_not_fit_is_simplified_harder_until_it_does_or_refused() {
        // A winding track with GPS noise, 20k points.
        let mut seed = 11u64;
        let mut noise = move || {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            ((seed >> 33) as f64) / ((1u64 << 31) as f64) - 0.5
        };
        let coords: Vec<Point> = (0..20_000)
            .map(|i| {
                let k = i as f64;
                Point {
                    latitude: 43.7 + k * 4e-6 + 0.004 * (k / 900.0).sin() + noise() * 4e-5,
                    longitude: 10.4 + k * 3e-6 + 0.006 * (k / 500.0).cos() + noise() * 4e-5,
                    altitude: None,
                }
            })
            .collect();
        let normal = build_with_limit(&input("w", coords.clone()), None, MAX_CONTENT_BYTES).unwrap();
        let tight = build_with_limit(&input("w", coords.clone()), None, normal.content_bytes / 2).unwrap();
        assert!(tight.content_bytes <= normal.content_bytes / 2);
        assert!(tight.report.tolerance_m > normal.report.tolerance_m, "tolerance must have been raised");
        assert!(build_with_limit(&input("w", coords), None, 200).unwrap_err().contains("too large"));
    }

    #[test]
    fn absurdly_long_tracks_are_refused_up_front() {
        let many = vec![Point { latitude: 1.0, longitude: 1.0, altitude: None }; MAX_INPUT_POINTS + 1];
        assert!(build(&input("m", many), None).unwrap_err().contains("too many points"));
    }

    #[test]
    fn explore_filters_by_distance_length_activity_and_difficulty_and_orders_by_closeness() {
        let (a, b) = (keys::generate(), keys::generate());
        let near = publish(&a, &input("near", walk(43.70, 10.40, 400, 5e-5, 0.1)), 10); // ~2 km, easy
        let mut bike = input("bike", walk(43.72, 10.42, 400, 5e-5, 0.1));
        bike.activity = Activity::Bike;
        let bike = publish(&a, &bike, 10);
        let hard = publish(&b, &input("hard", walk(43.74, 10.40, 1500, 4e-4, 1.0)), 10); // long + climb
        let far = publish(&b, &input("far", walk(46.0, 12.0, 100, 5e-5, 0.0)), 10);
        let all = vec![near.clone(), bike.clone(), hard.clone(), far.clone(), near.clone()]; // duplicate on purpose
        let names = |q: &ExploreQuery| select(all.clone(), q).iter().map(|t| t.d_tag.clone()).collect::<Vec<_>>();

        let q = query(43.70, 10.40);
        assert_eq!(names(&q), ["near", "bike", "hard"], "far is outside the radius, duplicate is merged");
        assert_eq!(names(&ExploreQuery { activity: Some(Activity::Bike), ..q.clone() }), ["bike"]);
        assert_eq!(names(&ExploreQuery { difficulty: vec![Difficulty::Hard], ..q.clone() }), ["hard"]);
        assert_eq!(names(&ExploreQuery { min_length_km: Some(5.0), ..q.clone() }), ["hard"]);
        assert_eq!(names(&ExploreQuery { max_length_km: Some(5.0), ..q.clone() }), ["near", "bike"]);
        assert_eq!(names(&ExploreQuery { radius_km: 1.0, ..q.clone() }), ["near"]);
    }

    #[test]
    fn the_newest_version_of_a_reshared_trail_wins() {
        let k = keys::generate();
        let old = publish(&k, &ShareInput { name: "Old name".into(), ..input("t", walk(43.7, 10.4, 50, 5e-4, 0.0)) }, 100);
        let new = publish(&k, &ShareInput { name: "New name".into(), ..input("t", walk(43.7, 10.4, 50, 5e-4, 0.0)) }, 200);
        for order in [vec![old.clone(), new.clone()], vec![new.clone(), old.clone()]] {
            let r = select(order, &query(43.7, 10.4));
            assert_eq!(r.len(), 1);
            assert_eq!(r[0].name, "New name");
        }
    }

    #[test]
    fn relay_filter_asks_for_the_right_kind_cells_and_activity() {
        let mut q = query(43.7, 10.4);
        q.activity = Some(Activity::Bike);
        let json = serde_json::to_value(relay_filter(&q)).unwrap();
        assert_eq!(json["kinds"], serde_json::json!([TRAIL_KIND]));
        assert!(json["#g"].as_array().unwrap().len() <= 9 && !json["#g"].as_array().unwrap().is_empty());
        assert_eq!(json["#t"], serde_json::json!(["bike"]));
        assert!(ExploreQuery { radius_km: 0.0, ..q.clone() }.validate().is_err());
        assert!(ExploreQuery { lat: 95.0, ..q }.validate().is_err());
    }

    #[test]
    fn deletion_points_at_the_addressable_event() {
        let k = keys::generate();
        let d = deletion(&k.public_key(), " my-trail ", Some(1));
        assert_eq!(d.kind, 5);
        assert_eq!(d.tags[0][1], format!("{TRAIL_KIND}:{}:my-trail", k.public_key().to_hex()));
    }
}

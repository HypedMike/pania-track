//! Looking at many trails together: which are the same route (and how the times compare), and
//! a heatmap of where the person has been.

use std::collections::{HashMap, HashSet};

use serde::{Deserialize, Serialize};

use super::geo::{Activity, Fix, Local, METERS_PER_DEGREE, resample, sanitize};
use super::motion::analyze;
use super::pace::track_adjusted_speed;

/// Points of two tracks closer than this are on the same path (m).
pub const MATCH_DISTANCE_M: f64 = 35.0;
/// Tracks are compared at a point every this many meters.
const SAMPLE_M: f64 = 20.0;
/// Both tracks must be this much covered by the other to be the same route.
pub const MIN_OVERLAP: f64 = 0.8;
const MAX_HEAT_CELLS: usize = 20_000;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrailInput {
    pub id: String,
    #[serde(default)]
    pub activity: Activity,
    pub fixes: Vec<Fix>,
}

struct Prepared {
    id: String,
    activity: Activity,
    /// (lat, lon, along m)
    samples: Vec<(f64, f64, f64)>,
    length_m: f64,
    start_ms: Option<i64>,
    fixes: Vec<Fix>,
    bbox: (f64, f64, f64, f64), // min lat, min lon, max lat, max lon
}

fn prepare(t: &TrailInput) -> Option<Prepared> {
    let fixes = sanitize(&t.fixes);
    let samples = resample(&fixes, SAMPLE_M);
    if samples.len() < 2 {
        return None;
    }
    let length_m = samples.last()?.2;
    let (mut a, mut b, mut c, mut d) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
    for s in &samples {
        a = a.min(s.0);
        b = b.min(s.1);
        c = c.max(s.0);
        d = d.max(s.1);
    }
    Some(Prepared {
        id: t.id.clone(),
        activity: t.activity,
        start_ms: fixes.first().and_then(|f| f.time_ms),
        samples,
        length_m,
        fixes,
        bbox: (a, b, c, d),
    })
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Overlap {
    /// Share of A's length that lies on B, and the other way round (0–1).
    pub a_on_b: f64,
    pub b_on_a: f64,
    /// B is walked in the opposite direction to A.
    pub reversed: bool,
}

impl Overlap {
    pub fn is_same_route(&self, min: f64) -> bool {
        self.a_on_b >= min && self.b_on_a >= min
    }
}

fn boxes_near(a: &Prepared, b: &Prepared) -> bool {
    let pad = MATCH_DISTANCE_M / METERS_PER_DEGREE * 1.5;
    a.bbox.0 - pad <= b.bbox.2
        && b.bbox.0 - pad <= a.bbox.2
        && a.bbox.1 - pad <= b.bbox.3
        && b.bbox.1 - pad <= a.bbox.3
}

/// For each sample of `from`, the index of the nearest sample of `to` within the match distance.
fn nearest_matches(
    local: &Local,
    from: &[(f64, f64, f64)],
    to: &[(f64, f64, f64)],
) -> Vec<Option<usize>> {
    let cell = MATCH_DISTANCE_M;
    let mut grid: HashMap<(i64, i64), Vec<usize>> = HashMap::new();
    let xy = |p: &(f64, f64, f64)| local.xy(p.0, p.1);
    for (i, p) in to.iter().enumerate() {
        let (x, y) = xy(p);
        grid.entry(((x / cell).floor() as i64, (y / cell).floor() as i64))
            .or_default()
            .push(i);
    }
    from.iter()
        .map(|p| {
            let (x, y) = xy(p);
            let (cx, cy) = ((x / cell).floor() as i64, (y / cell).floor() as i64);
            let mut best: Option<(f64, usize)> = None;
            for dx in -1..=1 {
                for dy in -1..=1 {
                    for &j in grid.get(&(cx + dx, cy + dy)).into_iter().flatten() {
                        let (qx, qy) = xy(&to[j]);
                        let d = ((qx - x).powi(2) + (qy - y).powi(2)).sqrt();
                        if d <= MATCH_DISTANCE_M && best.map_or(true, |(bd, _)| d < bd) {
                            best = Some((d, j));
                        }
                    }
                }
            }
            best.map(|(_, j)| j)
        })
        .collect()
}

fn overlap(a: &Prepared, b: &Prepared) -> Option<Overlap> {
    if !boxes_near(a, b) {
        return None;
    }
    let local = Local::around(a.samples[0].0);
    let a_to_b = nearest_matches(&local, &a.samples, &b.samples);
    let b_to_a = nearest_matches(&local, &b.samples, &a.samples);
    let share =
        |m: &[Option<usize>]| m.iter().filter(|x| x.is_some()).count() as f64 / m.len() as f64;
    let first = a_to_b.iter().find_map(|m| *m);
    let last = a_to_b.iter().rev().find_map(|m| *m);
    let reversed = matches!((first, last), (Some(f), Some(l)) if f > l);
    Some(Overlap {
        a_on_b: share(&a_to_b),
        b_on_a: share(&b_to_a),
        reversed,
    })
}

/// How much two trails overlap, and in which direction; `None` when they are far apart.
pub fn compare(a: &TrailInput, b: &TrailInput) -> Option<Overlap> {
    overlap(&prepare(a)?, &prepare(b)?)
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Member {
    pub id: String,
    /// Walked in the opposite direction to the first trail of the group.
    pub reversed: bool,
    pub distance_m: f64,
    pub start_ms: Option<i64>,
    pub moving_s: Option<f64>,
    pub elapsed_s: Option<f64>,
    /// Slope-adjusted moving speed, m/s.
    pub adjusted_speed_ms: Option<f64>,
    /// Slower than the group's best, in percent (0 for the best).
    pub vs_best_pct: Option<f64>,
    pub is_best: bool,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RouteGroup {
    pub members: Vec<Member>,
    /// The fastest member by moving time, when any has times.
    pub best_id: Option<String>,
}

/// Groups trails that follow the same route (each at least `min_overlap` covered by the group's
/// first trail and vice versa, in either direction). Only groups of two or more are returned,
/// largest first. Times are compared as moving time.
pub fn group_routes(trails: &[TrailInput], min_overlap: f64) -> Vec<RouteGroup> {
    let min_overlap = if min_overlap.is_finite() {
        min_overlap.clamp(0.3, 1.0)
    } else {
        MIN_OVERLAP
    };
    let mut prepared: Vec<Prepared> = trails.iter().filter_map(prepare).collect();
    prepared.sort_by_key(|p| p.start_ms.unwrap_or(i64::MAX));

    // (leader index, [(member index, reversed)])
    let mut groups: Vec<(usize, Vec<(usize, bool)>)> = Vec::new();
    for i in 0..prepared.len() {
        let found = groups.iter().position(|(leader, _)| {
            overlap(&prepared[*leader], &prepared[i]).is_some_and(|o| o.is_same_route(min_overlap))
        });
        match found {
            Some(g) => {
                let reversed = overlap(&prepared[groups[g].0], &prepared[i])
                    .map(|o| o.reversed)
                    .unwrap_or(false);
                groups[g].1.push((i, reversed));
            }
            None => groups.push((i, vec![(i, false)])),
        }
    }

    let mut out: Vec<RouteGroup> = groups
        .into_iter()
        .filter(|(_, m)| m.len() >= 2)
        .map(|(_, members)| {
            let mut rows: Vec<Member> = members
                .iter()
                .map(|&(i, reversed)| {
                    let p = &prepared[i];
                    let m = analyze(&p.fixes);
                    Member {
                        id: p.id.clone(),
                        reversed,
                        distance_m: p.length_m,
                        start_ms: p.start_ms,
                        moving_s: m.has_time.then_some(m.moving_s).filter(|s| *s > 0.0),
                        elapsed_s: m.has_time.then_some(m.elapsed_s),
                        adjusted_speed_ms: track_adjusted_speed(p.activity, &m),
                        vs_best_pct: None,
                        is_best: false,
                    }
                })
                .collect();
            let best = rows
                .iter()
                .filter_map(|r| r.moving_s)
                .fold(f64::MAX, f64::min);
            let mut best_id = None;
            if best < f64::MAX {
                for r in &mut rows {
                    if let Some(s) = r.moving_s {
                        r.vs_best_pct = Some((s / best - 1.0) * 100.0);
                        if (s - best).abs() < 1e-9 && best_id.is_none() {
                            r.is_best = true;
                            best_id = Some(r.id.clone());
                        }
                    }
                }
            }
            RouteGroup {
                members: rows,
                best_id,
            }
        })
        .collect();
    out.sort_by(|a, b| b.members.len().cmp(&a.members.len()));
    out
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HeatCell {
    pub latitude: f64,
    pub longitude: f64,
    /// How many different trails pass through the cell.
    pub count: u32,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Heatmap {
    pub cell_m: f64,
    pub lat_step: f64,
    pub lon_step: f64,
    pub cells: Vec<HeatCell>,
    pub max_count: u32,
    pub trails: usize,
    /// Area of the cells that were visited, a rough measure of how much ground was covered.
    pub explored_km2: f64,
    /// min lat, min lon, max lat, max lon of everything visited.
    pub bounds: Option<[f64; 4]>,
}

/// How often each cell of a grid was visited. A trail counts once per cell, however long it stays there.
pub fn heatmap(trails: &[TrailInput], cell_m: f64) -> Heatmap {
    let cell_m = if cell_m.is_finite() {
        cell_m.clamp(20.0, 5_000.0)
    } else {
        200.0
    };
    let tracks: Vec<Vec<Fix>> = trails
        .iter()
        .map(|t| sanitize(&t.fixes))
        .filter(|f| !f.is_empty())
        .collect();
    let all: Vec<&Fix> = tracks.iter().flatten().collect();
    if all.is_empty() {
        return Heatmap {
            cell_m,
            lat_step: 0.0,
            lon_step: 0.0,
            cells: vec![],
            max_count: 0,
            trails: 0,
            explored_km2: 0.0,
            bounds: None,
        };
    }
    let mean_lat = all.iter().map(|f| f.latitude).sum::<f64>() / all.len() as f64;
    let lat_step = cell_m / METERS_PER_DEGREE;
    let lon_step = lat_step / mean_lat.to_radians().cos().max(0.01);

    let mut counts: HashMap<(i64, i64), u32> = HashMap::new();
    let (mut min_lat, mut min_lon, mut max_lat, mut max_lon) =
        (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
    for fixes in &tracks {
        let mut seen: HashSet<(i64, i64)> = HashSet::new();
        let points = if fixes.len() == 1 {
            vec![(fixes[0].latitude, fixes[0].longitude, 0.0)]
        } else {
            resample(fixes, cell_m / 2.0)
        };
        for (lat, lon, _) in points {
            seen.insert((
                (lat / lat_step).floor() as i64,
                (lon / lon_step).floor() as i64,
            ));
            min_lat = min_lat.min(lat);
            max_lat = max_lat.max(lat);
            min_lon = min_lon.min(lon);
            max_lon = max_lon.max(lon);
        }
        for c in seen {
            *counts.entry(c).or_insert(0) += 1;
        }
    }
    let mut cells: Vec<HeatCell> = counts
        .iter()
        .map(|(&(i, j), &count)| HeatCell {
            latitude: (i as f64 + 0.5) * lat_step,
            longitude: (j as f64 + 0.5) * lon_step,
            count,
        })
        .collect();
    let explored_km2 = cells.len() as f64 * cell_m * cell_m / 1e6;
    cells.sort_by(|a, b| {
        b.count
            .cmp(&a.count)
            .then(a.latitude.partial_cmp(&b.latitude).unwrap())
    });
    cells.truncate(MAX_HEAT_CELLS);
    let max_count = cells.first().map_or(0, |c| c.count);
    Heatmap {
        cell_m,
        lat_step,
        lon_step,
        cells,
        max_count,
        trails: tracks.len(),
        explored_km2,
        bounds: Some([min_lat, min_lon, max_lat, max_lon]),
    }
}

#[cfg(test)]
mod tests {
    use super::super::geo::test_support::*;
    use super::*;

    /// A trail going north from (46, 11 + east) for `len_m`, at `speed` m/s starting at `start_s`.
    fn trail(
        id: &str,
        east_m: f64,
        len_m: f64,
        speed: f64,
        start_s: i64,
        reversed: bool,
    ) -> TrailInput {
        let lon = 11.0 + east_m / (METERS_PER_DEGREE * 46f64.to_radians().cos());
        let n = (len_m / (speed * 5.0)).ceil() as i64;
        let mut fixes: Vec<Fix> = (0..=n)
            .map(|k| Fix {
                latitude: north((k as f64 * speed * 5.0).min(len_m)),
                longitude: lon,
                altitude: None,
                time_ms: Some((start_s + k * 5) * 1000),
                accuracy: None,
            })
            .collect();
        if reversed {
            fixes.reverse();
            for (k, f) in fixes.iter_mut().enumerate() {
                f.time_ms = Some((start_s + k as i64 * 5) * 1000);
            }
        }
        TrailInput {
            id: id.into(),
            activity: Activity::Foot,
            fixes,
        }
    }

    #[test]
    fn identical_and_nearby_trails_overlap_fully() {
        let a = trail("a", 0.0, 2000.0, 1.2, 0, false);
        let b = trail("b", 10.0, 2000.0, 1.0, 0, false);
        let o = compare(&a, &b).unwrap();
        assert!(o.a_on_b > 0.97 && o.b_on_a > 0.97, "{o:?}");
        assert!(!o.reversed);
        assert!(o.is_same_route(MIN_OVERLAP));
    }

    #[test]
    fn the_other_direction_is_detected() {
        let a = trail("a", 0.0, 2000.0, 1.2, 0, false);
        let b = trail("b", 5.0, 2000.0, 1.2, 0, true);
        let o = compare(&a, &b).unwrap();
        assert!(o.is_same_route(MIN_OVERLAP));
        assert!(o.reversed);
    }

    #[test]
    fn a_trail_that_shares_only_part_is_not_the_same_route() {
        let a = trail("a", 0.0, 2000.0, 1.2, 0, false);
        let b = trail("b", 0.0, 800.0, 1.2, 0, false); // 40% of A, all of B
        let o = compare(&a, &b).unwrap();
        assert!(o.b_on_a > 0.95);
        assert!(o.a_on_b < 0.5);
        assert!(!o.is_same_route(MIN_OVERLAP));
    }

    #[test]
    fn far_apart_trails_do_not_overlap() {
        let a = trail("a", 0.0, 1000.0, 1.0, 0, false);
        let b = trail("b", 500.0, 1000.0, 1.0, 0, false);
        let o = compare(&a, &b);
        assert!(o.map_or(true, |o| o.a_on_b < 0.05 && o.b_on_a < 0.05));
    }

    #[test]
    fn groups_compare_times_and_find_the_best() {
        let trails = vec![
            trail("slow", 0.0, 2000.0, 1.0, 1_000, false),
            trail("fast", 8.0, 2000.0, 1.5, 100_000, false),
            trail("back", 3.0, 2000.0, 1.25, 200_000, true),
            trail("other", 900.0, 2000.0, 1.0, 300_000, false),
        ];
        let groups = group_routes(&trails, MIN_OVERLAP);
        assert_eq!(groups.len(), 1, "{groups:?}");
        let g = &groups[0];
        assert_eq!(g.members.len(), 3);
        assert_eq!(g.best_id.as_deref(), Some("fast"));
        let fast = g.members.iter().find(|m| m.id == "fast").unwrap();
        assert!(fast.is_best && fast.vs_best_pct == Some(0.0));
        let slow = g.members.iter().find(|m| m.id == "slow").unwrap();
        assert!(
            (slow.vs_best_pct.unwrap() - 50.0).abs() < 3.0,
            "{:?}",
            slow.vs_best_pct
        );
        assert!(g.members.iter().find(|m| m.id == "back").unwrap().reversed);
        assert!(g.members.iter().all(|m| m.id != "other"));
    }

    #[test]
    fn a_trail_alone_is_not_a_group() {
        assert!(group_routes(&[trail("a", 0.0, 1000.0, 1.0, 0, false)], MIN_OVERLAP).is_empty());
        assert!(group_routes(&[], MIN_OVERLAP).is_empty());
    }

    #[test]
    fn heatmap_counts_each_trail_once_per_cell() {
        let trails = vec![
            trail("a", 0.0, 2000.0, 1.0, 0, false),
            trail("b", 0.0, 2000.0, 1.0, 0, false),
            trail("c", 3000.0, 1000.0, 1.0, 0, false),
        ];
        let h = heatmap(&trails, 200.0);
        assert_eq!(h.trails, 3);
        assert_eq!(h.max_count, 2);
        assert!(h.cells.iter().filter(|c| c.count == 2).count() >= 9);
        assert!(h.cells.iter().all(|c| c.count >= 1));
        // 2 km + 1 km of path in 200 m cells: about 15 cells, ~0.6 km².
        assert!(
            h.explored_km2 > 0.4 && h.explored_km2 < 0.9,
            "{}",
            h.explored_km2
        );
        let b = h.bounds.unwrap();
        assert!(b[0] < b[2] && b[1] < b[3]);
    }

    #[test]
    fn heatmap_of_nothing_is_empty() {
        let h = heatmap(&[], 200.0);
        assert!(h.cells.is_empty() && h.bounds.is_none() && h.trails == 0);
        // Nonsense cell sizes are clamped.
        assert_eq!(heatmap(&[], f64::NAN).cell_m, 200.0);
    }

    #[test]
    fn a_single_point_trail_still_marks_a_cell() {
        let t = TrailInput {
            id: "p".into(),
            activity: Activity::Foot,
            fixes: vec![Fix::at(46.0, 11.0)],
        };
        let h = heatmap(&[t], 100.0);
        assert_eq!(h.cells.len(), 1);
    }
}

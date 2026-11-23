//! Climb breakdown: the track split into climbs, descents and flat stretches, the steepest
//! sustained kilometer, and how fast the person climbs (vertical meters per hour).

use serde::Serialize;

use super::geo::{Fix, cumulative_m, smoothed_altitudes};
use super::motion::{ALTITUDE_WINDOW_M, Motion};

/// A rise or fall smaller than this (m) is noise, not a climb.
pub const PROMINENCE_M: f64 = 15.0;
/// Between these slopes (percent) a stretch counts as flat.
pub const FLAT_GRADE_PCT: f64 = 3.0;
const SUSTAINED_M: f64 = 1_000.0;
/// A climb or descent that levels off for this long at its end (or start) has a flat stretch there.
const MIN_FLAT_M: f64 = 300.0;
/// Within this of the altitude at the end of a segment counts as level (m).
const LEVEL_M: f64 = 3.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Climb,
    Descent,
    Flat,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Segment {
    pub kind: Kind,
    pub start_index: usize,
    pub end_index: usize,
    pub start_m: f64,
    pub end_m: f64,
    pub distance_m: f64,
    /// Altitude change over the segment: positive for climbs, negative for descents.
    pub rise_m: f64,
    pub avg_grade_pct: f64,
    /// Moving time on the segment, when the track has times.
    pub duration_s: Option<f64>,
    /// Climbs only: vertical meters per hour of moving time.
    pub vertical_speed_mh: Option<f64>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Steep {
    pub start_m: f64,
    pub grade_pct: f64,
    pub rise_m: f64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Climbs {
    pub segments: Vec<Segment>,
    pub total_gain_m: f64,
    pub total_loss_m: f64,
    /// Steepest 1 km going up and going down; `None` for tracks shorter than a kilometer.
    pub steepest_climb_km: Option<Steep>,
    pub steepest_descent_km: Option<Steep>,
    /// All climbing divided by all time spent climbing, in vertical meters per hour.
    pub avg_vertical_speed_mh: Option<f64>,
}

/// Splits the track at its peaks and valleys. `None` when there is no altitude.
pub fn analyze(fixes: &[Fix], motion: &Motion) -> Option<Climbs> {
    if fixes.len() < 2 {
        return None;
    }
    let cum = cumulative_m(fixes);
    let alt = smoothed_altitudes(fixes, &cum, ALTITUDE_WINDOW_M)?;
    let n = fixes.len();

    // Zigzag: a pivot is a peak or valley that the track then leaves by at least PROMINENCE_M.
    let mut pivots = vec![0usize];
    let (mut lo, mut hi) = (0usize, 0usize);
    let mut dir = 0i8;
    let mut ext = 0usize;
    for i in 1..n {
        match dir {
            0 => {
                if alt[i] < alt[lo] {
                    lo = i;
                }
                if alt[i] > alt[hi] {
                    hi = i;
                }
                if alt[i] - alt[lo] >= PROMINENCE_M {
                    if lo != 0 {
                        pivots.push(lo);
                    }
                    dir = 1;
                    ext = i;
                } else if alt[hi] - alt[i] >= PROMINENCE_M {
                    if hi != 0 {
                        pivots.push(hi);
                    }
                    dir = -1;
                    ext = i;
                }
            }
            1 => {
                if alt[i] >= alt[ext] {
                    ext = i;
                } else if alt[ext] - alt[i] >= PROMINENCE_M {
                    pivots.push(ext);
                    dir = -1;
                    ext = i;
                }
            }
            _ => {
                if alt[i] <= alt[ext] {
                    ext = i;
                } else if alt[i] - alt[ext] >= PROMINENCE_M {
                    pivots.push(ext);
                    dir = 1;
                    ext = i;
                }
            }
        }
    }
    if *pivots.last().unwrap() != n - 1 {
        pivots.push(n - 1);
    }

    // A climb or descent that levels off, or starts level, gets its flat stretch as a segment of
    // its own: the zigzag alone only splits where the altitude turns around.
    let mut refined = vec![pivots[0]];
    for w in pivots.windows(2) {
        let (s, e) = (w[0], w[1]);
        let mut start = s;
        while start < e && (alt[start] - alt[s]).abs() <= LEVEL_M {
            start += 1;
        }
        let mut end = e;
        while end > s && (alt[end] - alt[e]).abs() <= LEVEL_M {
            end -= 1;
        }
        // `start`/`end` are the first/last fixes that left the level of the segment's ends.
        if start > s && cum[start] - cum[s] >= MIN_FLAT_M && start < end {
            refined.push(start - 1);
        }
        if end < e && cum[e] - cum[end] >= MIN_FLAT_M && end > *refined.last().unwrap() {
            refined.push(end + 1);
        }
        refined.push(e);
    }
    let pivots = refined;

    let mut segments: Vec<Segment> = Vec::new();
    for w in pivots.windows(2) {
        let (s, e) = (w[0], w[1]);
        let distance = cum[e] - cum[s];
        if distance <= 0.0 {
            continue;
        }
        let rise = alt[e] - alt[s];
        let grade = rise / distance * 100.0;
        let kind = if grade > FLAT_GRADE_PCT {
            Kind::Climb
        } else if grade < -FLAT_GRADE_PCT {
            Kind::Descent
        } else {
            Kind::Flat
        };
        // Neighboring flat stretches are one flat stretch.
        if kind == Kind::Flat {
            if let Some(prev) = segments.last_mut().filter(|p| p.kind == Kind::Flat) {
                prev.end_index = e;
                prev.end_m = cum[e];
                prev.distance_m = prev.end_m - prev.start_m;
                prev.rise_m = alt[e] - alt[prev.start_index];
                prev.avg_grade_pct = prev.rise_m / prev.distance_m * 100.0;
                continue;
            }
        }
        segments.push(Segment {
            kind,
            start_index: s,
            end_index: e,
            start_m: cum[s],
            end_m: cum[e],
            distance_m: distance,
            rise_m: rise,
            avg_grade_pct: grade,
            duration_s: None,
            vertical_speed_mh: None,
        });
    }

    // Moving time of each segment, from the legs that lie inside it.
    if motion.has_time {
        for seg in &mut segments {
            let t: f64 = motion
                .legs
                .iter()
                .filter(|l| l.start >= seg.start_index && l.end <= seg.end_index)
                .map(|l| l.time_s)
                .sum();
            if t > 0.0 {
                seg.duration_s = Some(t);
                if seg.kind == Kind::Climb {
                    seg.vertical_speed_mh = Some(seg.rise_m / (t / 3600.0));
                }
            }
        }
    }

    let total_gain_m: f64 = segments
        .iter()
        .filter(|s| s.rise_m > 0.0)
        .map(|s| s.rise_m)
        .sum();
    let total_loss_m: f64 = segments
        .iter()
        .filter(|s| s.rise_m < 0.0)
        .map(|s| -s.rise_m)
        .sum();
    let (climb_rise, climb_time) = segments
        .iter()
        .filter(|s| s.kind == Kind::Climb)
        .filter_map(|s| s.duration_s.map(|t| (s.rise_m, t)))
        .fold((0.0, 0.0), |(r, t), (sr, st)| (r + sr, t + st));
    let avg_vertical_speed_mh = if climb_time > 0.0 {
        Some(climb_rise / (climb_time / 3600.0))
    } else {
        None
    };

    let (steepest_climb_km, steepest_descent_km) = steepest_km(&cum, &alt);
    Some(Climbs {
        segments,
        total_gain_m,
        total_loss_m,
        steepest_climb_km,
        steepest_descent_km,
        avg_vertical_speed_mh,
    })
}

/// The steepest 1 km window going up and going down.
fn steepest_km(cum: &[f64], alt: &[f64]) -> (Option<Steep>, Option<Steep>) {
    let n = cum.len();
    let (mut best_up, mut best_down): (Option<Steep>, Option<Steep>) = (None, None);
    let mut j = 0usize;
    for i in 0..n {
        if j < i {
            j = i;
        }
        while j < n && cum[j] - cum[i] < SUSTAINED_M {
            j += 1;
        }
        if j >= n {
            break;
        }
        let len = cum[j] - cum[i];
        let rise = alt[j] - alt[i];
        let grade = rise / len * 100.0;
        let candidate = Steep {
            start_m: cum[i],
            grade_pct: grade,
            rise_m: rise,
        };
        if grade > 0.0 && best_up.as_ref().map_or(true, |b| grade > b.grade_pct) {
            best_up = Some(candidate.clone());
        }
        if grade < 0.0 && best_down.as_ref().map_or(true, |b| grade < b.grade_pct) {
            best_down = Some(candidate);
        }
    }
    (best_up, best_down)
}

#[cfg(test)]
mod tests {
    use super::super::geo::test_support::*;
    use super::super::motion::analyze as motion;
    use super::*;

    /// Meters of altitude at each 10 m of distance, walked at 1 m/s.
    fn track(alts: &[f64]) -> Vec<Fix> {
        alts.iter()
            .enumerate()
            .map(|(i, &a)| Fix {
                latitude: north(i as f64 * 10.0),
                longitude: 11.0,
                altitude: Some(a),
                time_ms: Some(i as i64 * 10_000),
                accuracy: None,
            })
            .collect()
    }

    /// Up `up` m over `len` m, then down by `down`, then flat for `flat` m.
    fn profile(len: usize, up: f64, down: f64, flat: usize) -> Vec<f64> {
        let mut v = vec![];
        let mut a = 1000.0;
        for _ in 0..len {
            a += up / len as f64;
            v.push(a);
        }
        for _ in 0..len {
            a -= down / len as f64;
            v.push(a);
        }
        for _ in 0..flat {
            v.push(a);
        }
        v
    }

    #[test]
    fn splits_into_climb_descent_and_flat() {
        let fixes = track(&profile(100, 200.0, 150.0, 80)); // 1 km up 200 m, 1 km down 150 m, 800 m flat
        let c = analyze(&fixes, &motion(&fixes)).unwrap();
        let kinds: Vec<Kind> = c.segments.iter().map(|s| s.kind).collect();
        assert_eq!(
            kinds,
            vec![Kind::Climb, Kind::Descent, Kind::Flat],
            "{:?}",
            c.segments
        );
        assert!((c.segments[0].rise_m - 200.0).abs() < 10.0);
        assert!((c.segments[0].avg_grade_pct - 20.0).abs() < 1.5);
        assert!((c.total_gain_m - 200.0).abs() < 10.0);
        assert!((c.total_loss_m - 150.0).abs() < 10.0);
    }

    #[test]
    fn vertical_speed_is_gain_over_moving_time() {
        let fixes = track(&profile(100, 300.0, 0.0, 0)); // 300 m in 1000 s of walking
        let c = analyze(&fixes, &motion(&fixes)).unwrap();
        let climb = &c.segments[0];
        assert!(
            (climb.vertical_speed_mh.unwrap() - 1080.0).abs() < 60.0,
            "{:?}",
            climb.vertical_speed_mh
        );
        assert!((c.avg_vertical_speed_mh.unwrap() - 1080.0).abs() < 60.0);
    }

    #[test]
    fn small_wiggles_are_not_climbs() {
        let alts: Vec<f64> = (0..200)
            .map(|i| 1000.0 + if i % 2 == 0 { 4.0 } else { -4.0 })
            .collect();
        let fixes = track(&alts);
        let c = analyze(&fixes, &motion(&fixes)).unwrap();
        assert_eq!(c.segments.len(), 1);
        assert_eq!(c.segments[0].kind, Kind::Flat);
    }

    #[test]
    fn steepest_kilometer_is_found_where_it_is() {
        // 1 km flat, 1 km at +15%, 1 km flat.
        let mut alts = vec![1000.0; 100];
        for i in 0..100 {
            alts.push(1000.0 + 1.5 * (i + 1) as f64);
        }
        alts.extend(vec![1150.0; 100]);
        let fixes = track(&alts);
        let c = analyze(&fixes, &motion(&fixes)).unwrap();
        let s = c.steepest_climb_km.unwrap();
        assert!((s.grade_pct - 15.0).abs() < 1.5, "{s:?}");
        assert!((s.start_m - 1000.0).abs() < 60.0, "{s:?}");
        assert!(c.steepest_descent_km.is_none());
    }

    #[test]
    fn short_tracks_have_no_steepest_kilometer() {
        let fixes = track(&profile(30, 40.0, 0.0, 0));
        let c = analyze(&fixes, &motion(&fixes)).unwrap();
        assert!(c.steepest_climb_km.is_none());
    }

    #[test]
    fn no_altitude_means_no_analysis() {
        let fixes = walk(1.0, 5, 600, 0);
        assert!(analyze(&fixes, &motion(&fixes)).is_none());
    }
}

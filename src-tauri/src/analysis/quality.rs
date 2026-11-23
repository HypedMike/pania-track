//! How trustworthy a recording is, and cleaning it up.
//!
//! Finds position spikes (a fix that jumps away and back), altitude jumps, gaps in the
//! recording and poor accuracy, and can remove them. Altitude from a phone GPS is noisy, so
//! cleaning also smooths it; a terrain model can replace it (the caller passes those values in).

use serde::Serialize;

use super::geo::{Activity, Fix, cumulative_m, distance_m, smoothed_altitudes};
use super::motion::gap_threshold_s;

/// An altitude this far from its neighbors' median is a jump (m).
pub const ALTITUDE_JUMP_M: f64 = 25.0;
/// Accuracy worse than this is poor (m).
pub const POOR_ACCURACY_M: f64 = 30.0;
/// Without times, a fix this far from both neighbors, which are close to each other, is a spike (m).
const SPIKE_JUMP_NO_TIME_M: f64 = 150.0;
/// Altitude smoothing window when cleaning (m of track).
const CLEAN_WINDOW_M: f64 = 30.0;
/// Altitude changes below this are noise in the gain (the same rule as the app's trail stats).
const GAIN_NOISE_M: f64 = 3.0;
const MAX_ISSUES: usize = 50;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum IssueKind {
    PositionSpike,
    AltitudeJump,
    Gap,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Issue {
    pub kind: IssueKind,
    /// Index of the fix (for a gap, of the fix after it).
    pub index: usize,
    /// Meters for a spike or jump, seconds for a gap.
    pub size: f64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Accuracy {
    pub median_m: f64,
    pub p95_m: f64,
    /// Share of fixes worse than [`POOR_ACCURACY_M`], 0–100.
    pub poor_pct: f64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Quality {
    pub points: usize,
    pub with_altitude_pct: f64,
    pub with_time_pct: f64,
    /// `None` for tracks recorded before accuracy was kept, and for imported ones.
    pub accuracy: Option<Accuracy>,
    pub spikes: usize,
    pub altitude_jumps: usize,
    pub gaps: usize,
    pub longest_gap_s: f64,
    /// 0–100, 100 being a clean recording.
    pub score: u32,
    /// Worth a look, and worth offering to clean.
    pub suspicious: bool,
    /// The first few problems, for showing where they are.
    pub issues: Vec<Issue>,
}

fn pct(count: usize, total: usize) -> f64 {
    if total == 0 {
        0.0
    } else {
        count as f64 * 100.0 / total as f64
    }
}

fn percentile(sorted: &[f64], p: f64) -> f64 {
    let idx = ((sorted.len() - 1) as f64 * p).round() as usize;
    sorted[idx]
}

/// Indices of fixes that jump away from the track and back.
pub fn find_spikes(fixes: &[Fix], activity: Activity) -> Vec<usize> {
    let mut out = Vec::new();
    for i in 1..fixes.len().saturating_sub(1) {
        let (a, b, c) = (&fixes[i - 1], &fixes[i], &fixes[i + 1]);
        let (d_in, d_out, d_skip) = (distance_m(a, b), distance_m(b, c), distance_m(a, c));
        if d_skip >= d_in.max(d_out) / 2.0 {
            continue; // the track really goes on past this fix
        }
        let fast = |from: &Fix, to: &Fix, d: f64| match (from.time_ms, to.time_ms) {
            (Some(t0), Some(t1)) if t1 > t0 => {
                d / ((t1 - t0) as f64 / 1000.0) > activity.max_speed_ms()
            }
            (Some(_), Some(_)) => d > 5.0,
            _ => d > SPIKE_JUMP_NO_TIME_M,
        };
        if fast(a, b, d_in) && fast(b, c, d_out) {
            out.push(i);
        }
    }
    out
}

/// Indices whose altitude is far from the median of the fixes around them.
pub fn find_altitude_jumps(fixes: &[Fix]) -> Vec<usize> {
    let mut out = Vec::new();
    for i in 0..fixes.len() {
        let Some(a) = fixes[i].altitude else { continue };
        let mut around: Vec<f64> = (i.saturating_sub(2)..=(i + 2).min(fixes.len() - 1))
            .filter(|&k| k != i)
            .filter_map(|k| fixes[k].altitude)
            .collect();
        if around.len() < 2 {
            continue;
        }
        around.sort_by(|x, y| x.partial_cmp(y).unwrap());
        let median = around[around.len() / 2];
        if (a - median).abs() > ALTITUDE_JUMP_M {
            out.push(i);
        }
    }
    out
}

pub fn assess(fixes: &[Fix], activity: Activity) -> Quality {
    let n = fixes.len();
    let with_alt = fixes.iter().filter(|f| f.altitude.is_some()).count();
    let timed: Vec<f64> = fixes
        .iter()
        .filter_map(|f| f.time_ms)
        .map(|t| t as f64 / 1000.0)
        .collect();

    let mut issues = Vec::new();
    let spikes = find_spikes(fixes, activity);
    for &i in &spikes {
        issues.push(Issue {
            kind: IssueKind::PositionSpike,
            index: i,
            size: distance_m(&fixes[i - 1], &fixes[i]),
        });
    }
    let jumps = find_altitude_jumps(fixes);
    for &i in &jumps {
        let a = fixes[i].altitude.unwrap_or(0.0);
        let near = fixes[i.saturating_sub(1)].altitude.unwrap_or(a);
        issues.push(Issue {
            kind: IssueKind::AltitudeJump,
            index: i,
            size: (a - near).abs(),
        });
    }
    let (mut gaps, mut longest) = (0usize, 0.0f64);
    if timed.len() >= 2 && timed.len() * 10 >= n * 9 {
        let threshold = gap_threshold_s(&timed);
        let mut last = None;
        for (i, f) in fixes.iter().enumerate() {
            let Some(t) = f.time_ms.map(|t| t as f64 / 1000.0) else {
                continue;
            };
            if let Some((_, lt)) = last {
                if t - lt > threshold {
                    gaps += 1;
                    longest = longest.max(t - lt);
                    issues.push(Issue {
                        kind: IssueKind::Gap,
                        index: i,
                        size: t - lt,
                    });
                }
            }
            last = Some((i, t));
        }
    }

    let mut accuracies: Vec<f64> = fixes
        .iter()
        .filter_map(|f| f.accuracy)
        .filter(|a| a.is_finite())
        .collect();
    let accuracy = if accuracies.is_empty() {
        None
    } else {
        accuracies.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let poor = accuracies.iter().filter(|a| **a > POOR_ACCURACY_M).count();
        Some(Accuracy {
            median_m: percentile(&accuracies, 0.5),
            p95_m: percentile(&accuracies, 0.95),
            poor_pct: pct(poor, accuracies.len()),
        })
    };

    let penalty = spikes.len() as f64 * 4.0
        + jumps.len() as f64 * 2.0
        + gaps as f64 * 2.0
        + accuracy.as_ref().map_or(0.0, |a| a.poor_pct * 0.4);
    let score = (100.0 - penalty).clamp(0.0, 100.0).round() as u32;
    issues.sort_by_key(|i| i.index);
    issues.truncate(MAX_ISSUES);
    Quality {
        points: n,
        with_altitude_pct: pct(with_alt, n),
        with_time_pct: pct(timed.len(), n),
        accuracy,
        spikes: spikes.len(),
        altitude_jumps: jumps.len(),
        gaps,
        longest_gap_s: longest,
        score,
        suspicious: score < 80 || !spikes.is_empty(),
        issues,
    }
}

/// Elevation gain with the same noise rule as the app's trail stats.
pub fn gain_m(altitudes: impl Iterator<Item = f64>) -> f64 {
    let mut gain = 0.0;
    let mut reference: Option<f64> = None;
    for a in altitudes {
        let r = *reference.get_or_insert(a);
        if a - r >= GAIN_NOISE_M {
            gain += a - r;
            reference = Some(a);
        } else if r - a >= GAIN_NOISE_M {
            reference = Some(a);
        }
    }
    gain
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Cleaned {
    pub fixes: Vec<Fix>,
    pub removed_points: usize,
    pub altitudes_changed: usize,
    pub gain_before_m: Option<f64>,
    pub gain_after_m: Option<f64>,
}

/// Removes position spikes, replaces altitude jumps and smooths the altitude. When `terrain`
/// has one value per original fix (from a terrain model), those replace the GPS altitude first.
pub fn clean(fixes: &[Fix], activity: Activity, terrain: Option<&[f64]>) -> Cleaned {
    let gain_before = {
        let g = gain_m(fixes.iter().filter_map(|f| f.altitude));
        fixes.iter().any(|f| f.altitude.is_some()).then_some(g)
    };
    let mut work: Vec<Fix> = fixes.to_vec();
    if let Some(t) = terrain.filter(|t| t.len() == work.len()) {
        for (f, &alt) in work.iter_mut().zip(t) {
            if alt.is_finite() {
                f.altitude = Some(alt);
            }
        }
    }
    let spikes = find_spikes(&work, activity);
    let mut keep = vec![true; work.len()];
    for &i in &spikes {
        keep[i] = false;
    }
    let mut out: Vec<Fix> = work
        .iter()
        .zip(&keep)
        .filter(|(_, k)| **k)
        .map(|(f, _)| f.clone())
        .collect();

    // Altitude: jumps take the median of their neighbors, then a light smoothing.
    let mut changed = 0;
    let jumps = find_altitude_jumps(&out);
    let medians: Vec<(usize, f64)> = jumps
        .iter()
        .filter_map(|&i| {
            let mut around: Vec<f64> = (i.saturating_sub(2)..=(i + 2).min(out.len() - 1))
                .filter(|&k| k != i)
                .filter_map(|k| out[k].altitude)
                .collect();
            around.sort_by(|a, b| a.partial_cmp(b).unwrap());
            around.get(around.len() / 2).map(|m| (i, *m))
        })
        .collect();
    for (i, m) in medians {
        out[i].altitude = Some(m);
    }
    let cum = cumulative_m(&out);
    if let Some(smooth) = smoothed_altitudes(&out, &cum, CLEAN_WINDOW_M) {
        for (f, s) in out.iter_mut().zip(smooth) {
            if let Some(a) = f.altitude {
                if (a - s).abs() > 1e-9 {
                    changed += 1;
                }
                f.altitude = Some((s * 10.0).round() / 10.0);
            }
        }
    }
    let gain_after = {
        let g = gain_m(out.iter().filter_map(|f| f.altitude));
        out.iter().any(|f| f.altitude.is_some()).then_some(g)
    };
    Cleaned {
        removed_points: fixes.len() - out.len(),
        altitudes_changed: changed,
        gain_before_m: gain_before,
        gain_after_m: gain_after,
        fixes: out,
    }
}

#[cfg(test)]
mod tests {
    use super::super::geo::test_support::*;
    use super::*;

    fn clean_walk() -> Vec<Fix> {
        let mut f = walk(1.2, 5, 600, 0);
        for (i, x) in f.iter_mut().enumerate() {
            x.altitude = Some(1000.0 + i as f64 * 0.1);
            x.accuracy = Some(8.0);
        }
        f
    }

    #[test]
    fn a_clean_recording_scores_100() {
        let q = assess(&clean_walk(), Activity::Foot);
        assert_eq!(q.score, 100);
        assert!(!q.suspicious);
        assert_eq!((q.spikes, q.altitude_jumps, q.gaps), (0, 0, 0));
        assert!((q.with_altitude_pct - 100.0).abs() < 1e-9);
        let acc = q.accuracy.unwrap();
        assert_eq!(acc.median_m, 8.0);
        assert_eq!(acc.poor_pct, 0.0);
    }

    #[test]
    fn a_fix_that_jumps_away_and_back_is_a_spike() {
        let mut f = clean_walk();
        f[40].latitude += 2000.0 / super::super::geo::METERS_PER_DEGREE; // 2 km away for one fix
        let q = assess(&f, Activity::Foot);
        assert_eq!(q.spikes, 1);
        assert_eq!(q.issues[0].kind, IssueKind::PositionSpike);
        assert_eq!(q.issues[0].index, 40);
        assert!(q.suspicious);
        assert!(q.score < 100);
    }

    #[test]
    fn real_fast_movement_is_not_a_spike() {
        // A bike at 15 m/s is fine, on foot it would not be.
        let f = walk(15.0, 5, 300, 0);
        assert_eq!(assess(&f, Activity::Bike).spikes, 0);
    }

    #[test]
    fn altitude_jumps_are_found() {
        let mut f = clean_walk();
        f[50].altitude = Some(1300.0);
        let q = assess(&f, Activity::Foot);
        assert_eq!(q.altitude_jumps, 1);
        assert_eq!(
            q.issues
                .iter()
                .find(|i| i.kind == IssueKind::AltitudeJump)
                .unwrap()
                .index,
            50
        );
    }

    #[test]
    fn gaps_and_poor_accuracy_count() {
        let mut f = clean_walk();
        for x in f.iter_mut().skip(60) {
            x.time_ms = x.time_ms.map(|t| t + 3_600_000);
        }
        for x in f.iter_mut().take(20) {
            x.accuracy = Some(80.0);
        }
        let q = assess(&f, Activity::Foot);
        assert_eq!(q.gaps, 1);
        assert!((q.longest_gap_s - 3_605.0).abs() < 10.0);
        let acc = q.accuracy.unwrap();
        assert!((acc.poor_pct - 20.0 / 121.0 * 100.0).abs() < 0.5);
        assert!(q.score < 100);
    }

    #[test]
    fn missing_accuracy_is_reported_as_unknown() {
        let q = assess(&walk(1.0, 5, 100, 0), Activity::Foot);
        assert!(q.accuracy.is_none());
        assert_eq!(q.with_altitude_pct, 0.0);
    }

    #[test]
    fn cleaning_removes_spikes_and_smooths_altitude() {
        let mut f = clean_walk();
        f[40].latitude += 2000.0 / super::super::geo::METERS_PER_DEGREE;
        f[50].altitude = Some(1300.0);
        for (i, x) in f.iter_mut().enumerate() {
            if i != 50 {
                x.altitude = x.altitude.map(|a| a + if i % 2 == 0 { 2.5 } else { -2.5 });
            }
        }
        let c = clean(&f, Activity::Foot, None);
        assert_eq!(c.removed_points, 1);
        assert_eq!(c.fixes.len(), f.len() - 1);
        assert!(
            assess(&c.fixes, Activity::Foot).spikes == 0
                && assess(&c.fixes, Activity::Foot).altitude_jumps == 0
        );
        // The zigzag no longer inflates the gain: it is close to the real 12 m.
        assert!(c.gain_before_m.unwrap() > c.gain_after_m.unwrap());
        assert!(
            (c.gain_after_m.unwrap() - 12.0).abs() < 5.0,
            "{:?}",
            c.gain_after_m
        );
        assert!(c.altitudes_changed > 0);
    }

    #[test]
    fn terrain_values_replace_gps_altitude() {
        let f = clean_walk();
        let terrain: Vec<f64> = (0..f.len()).map(|i| 2000.0 + i as f64).collect();
        let c = clean(&f, Activity::Foot, Some(&terrain));
        assert!(c.fixes.iter().all(|x| x.altitude.unwrap() > 1999.0));
        // A terrain list of the wrong length is ignored.
        let c2 = clean(&f, Activity::Foot, Some(&terrain[..5]));
        assert!(c2.fixes[0].altitude.unwrap() < 1100.0);
    }

    #[test]
    fn gain_ignores_small_changes() {
        assert_eq!(gain_m([100.0, 101.0, 102.0, 101.0].into_iter()), 0.0);
        assert_eq!(gain_m([100.0, 104.0, 110.0].into_iter()), 10.0);
        assert_eq!(gain_m(std::iter::empty()), 0.0);
    }
}

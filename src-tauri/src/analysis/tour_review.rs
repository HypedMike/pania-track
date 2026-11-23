//! Looking back at a tour: how the time compares to the plan, kilometer by kilometer, and
//! where it was won or lost.

use serde::{Deserialize, Serialize};

use super::geo::{Fix, Local, cumulative_m, sanitize};
use super::motion::analyze;
use super::pace::Profile;

/// More than this from the trail and the person was not following it (m).
pub const OFF_TRAIL_M: f64 = 50.0;
/// Fixes this far away say nothing about progress along the trail (m).
const LOST_M: f64 = 150.0;
/// Without a stronger hint the nearest point is searched this far around the last known one (m).
const SEARCH_BACK_M: f64 = 100.0;
const SEARCH_AHEAD_M: f64 = 1_000.0;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Plan {
    /// Constant planned speed, m/s, used when there is no profile.
    pub speed_ms: f64,
    /// Planned cumulative time along the trail, which accounts for the slopes.
    #[serde(default)]
    pub profile: Option<Profile>,
}

impl Plan {
    fn seconds_at(&self, along_m: f64) -> f64 {
        match &self.profile {
            Some(p) if !p.seconds.is_empty() => p.seconds_at(along_m),
            _ => along_m / self.speed_ms.max(0.05),
        }
    }
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Split {
    pub from_m: f64,
    pub to_m: f64,
    pub planned_s: f64,
    pub actual_s: f64,
    /// Positive: slower than planned.
    pub delta_s: f64,
    /// Running total of the deltas up to the end of this split.
    pub cumulative_delta_s: f64,
    /// Time stood still inside the split.
    pub stopped_s: f64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Review {
    /// The whole trail was covered (at least 95%).
    pub completed: bool,
    pub trail_length_m: f64,
    /// How far along the trail the person got.
    pub covered_m: f64,
    pub planned_s: f64,
    pub actual_s: f64,
    /// Positive: slower than planned.
    pub delta_s: f64,
    pub moving_s: f64,
    pub stopped_s: f64,
    pub off_trail_s: f64,
    pub splits: Vec<Split>,
    /// Index of the split that lost the most time, and of the one that gained the most.
    pub worst_split: Option<usize>,
    pub best_split: Option<usize>,
}

struct Sample {
    time_s: f64,
    along_m: f64,
    off_m: f64,
}

/// Nearest point of the trail to a position: (distance from it, meters along it).
fn project(
    trail: &[Fix],
    cum: &[f64],
    local: &Local,
    fix: &Fix,
    window: Option<(f64, f64)>,
) -> (f64, f64) {
    let (px, py) = local.xy(fix.latitude, fix.longitude);
    let mut best = (f64::MAX, 0.0);
    for i in 0..trail.len().saturating_sub(1) {
        if let Some((lo, hi)) = window {
            if cum[i + 1] < lo || cum[i] > hi {
                continue;
            }
        }
        let (ax, ay) = local.xy(trail[i].latitude, trail[i].longitude);
        let (bx, by) = local.xy(trail[i + 1].latitude, trail[i + 1].longitude);
        let (dx, dy) = (bx - ax, by - ay);
        let len2 = dx * dx + dy * dy;
        let f = if len2 > 0.0 {
            (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let d = ((ax + dx * f - px).powi(2) + (ay + dy * f - py).powi(2)).sqrt();
        if d < best.0 {
            best = (d, cum[i] + (cum[i + 1] - cum[i]) * f);
        }
    }
    best
}

/// Time at which the person was at `along_m`, by interpolation. Needs `samples` sorted by along.
fn time_at(samples: &[(f64, f64)], along_m: f64) -> Option<f64> {
    let idx = samples.partition_point(|s| s.0 < along_m);
    if idx == 0 {
        return samples
            .first()
            .filter(|s| (s.0 - along_m).abs() < 1e-9 || s.0 > along_m)
            .map(|s| s.1);
    }
    let (a, b) = (samples.get(idx - 1)?, samples.get(idx)?);
    let f = if b.0 > a.0 {
        (along_m - a.0) / (b.0 - a.0)
    } else {
        0.0
    };
    Some(a.1 + (b.1 - a.1) * f)
}

fn split_length(total: f64) -> f64 {
    if total >= 5_000.0 {
        1_000.0
    } else if total >= 2_000.0 {
        500.0
    } else {
        250.0
    }
}

/// Compares a recorded tour with the plan. `None` when there is too little to compare.
pub fn review(trail: &[Fix], run: &[Fix], plan: &Plan) -> Option<Review> {
    let trail = sanitize(trail);
    let run = sanitize(run);
    if trail.len() < 2 || run.len() < 2 {
        return None;
    }
    let cum = cumulative_m(&trail);
    let length = *cum.last()?;
    if length <= 0.0 {
        return None;
    }
    let local = Local::around(trail[0].latitude);
    let t0 = run.iter().find_map(|f| f.time_ms)? as f64 / 1000.0;

    let mut samples: Vec<Sample> = Vec::new();
    let mut last_along = 0.0f64;
    for f in &run {
        let Some(t) = f.time_ms else { continue };
        let near = project(
            &trail,
            &cum,
            &local,
            f,
            Some((last_along - SEARCH_BACK_M, last_along + SEARCH_AHEAD_M)),
        );
        let (off, along) = if near.0 <= LOST_M {
            near
        } else {
            project(&trail, &cum, &local, f, None)
        };
        samples.push(Sample {
            time_s: t as f64 / 1000.0 - t0,
            along_m: along,
            off_m: off,
        });
        if off <= LOST_M {
            last_along = last_along.max(along);
        }
    }
    if samples.len() < 2 {
        return None;
    }

    // Progress along the trail never goes back, and only fixes near the trail count.
    let mut progress: Vec<(f64, f64)> = Vec::new();
    let mut best_along = 0.0f64;
    for s in samples.iter().filter(|s| s.off_m <= LOST_M) {
        best_along = best_along.max(s.along_m);
        if progress.last().map_or(true, |p| best_along > p.0) {
            progress.push((best_along, s.time_s));
        }
        // Standing at a spot already reached adds nothing: the time of arrival is what counts, and
        // the wait shows up in the stretch between this spot and the next one.
    }
    let covered = progress.last().map(|p| p.0).unwrap_or(0.0);
    if progress.len() < 2 || covered < 50.0 {
        return None;
    }
    let completed = covered >= length * 0.95;

    // Time the person started moving along the trail, not the time they pressed play.
    let start_s = progress[0].1;
    let split_m = split_length(length);
    let mut splits = Vec::new();
    let motion = analyze(&run);
    let mut from = 0.0;
    let mut cumulative = 0.0;
    while from < covered - 1.0 {
        let to = (from + split_m).min(covered);
        // The last stretch of a trail is not made a split of its own when it is tiny.
        if let (Some(a), Some(b)) = (
            time_at(&progress, from.max(progress[0].0)),
            time_at(&progress, to),
        ) {
            let actual = b - a;
            let planned = plan.seconds_at(to) - plan.seconds_at(from);
            let stopped: f64 = motion
                .stops
                .iter()
                .filter_map(|st| {
                    let s0 = st.start_ms.map(|v| v as f64 / 1000.0 - t0)?;
                    let s1 = s0 + st.duration_s;
                    let overlap = (s1.min(b + start_s) - s0.max(a + start_s)).max(0.0);
                    Some(overlap)
                })
                .sum();
            cumulative += actual - planned;
            splits.push(Split {
                from_m: from,
                to_m: to,
                planned_s: planned,
                actual_s: actual,
                delta_s: actual - planned,
                cumulative_delta_s: cumulative,
                stopped_s: stopped,
            });
        }
        from = to;
    }

    let actual_s = splits.iter().map(|s| s.actual_s).sum::<f64>();
    let planned_s = splits.iter().map(|s| s.planned_s).sum::<f64>();
    let off_trail_s = samples
        .windows(2)
        .filter(|w| w[0].off_m > OFF_TRAIL_M && w[1].off_m > OFF_TRAIL_M)
        .map(|w| w[1].time_s - w[0].time_s)
        .filter(|d| *d > 0.0 && *d < 600.0)
        .sum();
    let worst = splits
        .iter()
        .enumerate()
        .max_by(|a, b| a.1.delta_s.partial_cmp(&b.1.delta_s).unwrap())
        .map(|(i, s)| (i, s.delta_s));
    let best = splits
        .iter()
        .enumerate()
        .min_by(|a, b| a.1.delta_s.partial_cmp(&b.1.delta_s).unwrap())
        .map(|(i, s)| (i, s.delta_s));
    Some(Review {
        completed,
        trail_length_m: length,
        covered_m: covered,
        planned_s,
        actual_s,
        delta_s: actual_s - planned_s,
        moving_s: motion.moving_s,
        stopped_s: motion.stopped_s,
        off_trail_s,
        worst_split: worst.filter(|(_, d)| *d > 0.0).map(|(i, _)| i),
        best_split: best.filter(|(_, d)| *d < 0.0).map(|(i, _)| i),
        splits,
    })
}

#[cfg(test)]
mod tests {
    use super::super::geo::METERS_PER_DEGREE;
    use super::super::geo::test_support::*;
    use super::*;

    fn trail(len_m: f64) -> Vec<Fix> {
        (0..=(len_m / 10.0) as usize)
            .map(|i| Fix::at(north(i as f64 * 10.0), 11.0))
            .collect()
    }

    /// A run along the trail: `legs` are (length_m, speed_ms); `pause_at_m` adds a stop there.
    fn run(legs: &[(f64, f64)], pauses: &[(f64, f64)]) -> Vec<Fix> {
        let mut fixes = Vec::new();
        let (mut d, mut t) = (0.0, 0.0);
        let push = |d: f64, t: f64, fixes: &mut Vec<Fix>| {
            fixes.push(Fix {
                latitude: north(d),
                longitude: 11.0,
                altitude: None,
                time_ms: Some((t * 1000.0) as i64),
                accuracy: None,
            });
        };
        push(d, t, &mut fixes);
        for &(len, speed) in legs {
            let end = d + len;
            while d < end - 1e-9 {
                let step = (speed * 5.0).min(end - d);
                d += step;
                t += step / speed;
                push(d, t, &mut fixes);
                if let Some(&(_, secs)) = pauses.iter().find(|(at, _)| d >= *at && d - step < *at) {
                    let until = t + secs;
                    while t < until {
                        t += 5.0;
                        push(d, t, &mut fixes);
                    }
                }
            }
        }
        fixes
    }

    fn plan(speed: f64) -> Plan {
        Plan {
            speed_ms: speed,
            profile: None,
        }
    }

    #[test]
    fn on_plan_means_no_difference() {
        let r = review(&trail(4000.0), &run(&[(4000.0, 1.0)], &[]), &plan(1.0)).unwrap();
        assert!(r.completed);
        assert!(r.delta_s.abs() < 15.0, "{}", r.delta_s);
        assert_eq!(r.splits.len(), 8); // 500 m splits for a 4 km trail
        assert!(r.splits.iter().all(|s| s.delta_s.abs() < 8.0));
        assert!(r.worst_split.is_none() || r.splits[r.worst_split.unwrap()].delta_s < 8.0);
    }

    #[test]
    fn the_slow_stretch_is_where_the_time_is_lost() {
        // 1 km at plan pace, 1 km at half speed, 2 km at plan pace.
        let r = review(
            &trail(4000.0),
            &run(&[(1000.0, 1.0), (1000.0, 0.5), (2000.0, 1.0)], &[]),
            &plan(1.0),
        )
        .unwrap();
        assert!((r.delta_s - 1000.0).abs() < 30.0, "{}", r.delta_s);
        let worst = &r.splits[r.worst_split.unwrap()];
        assert!(worst.from_m >= 999.0 && worst.to_m <= 2001.0, "{worst:?}");
        assert!(
            (worst.delta_s - 500.0).abs() < 30.0 || (worst.delta_s - 250.0).abs() < 30.0,
            "{worst:?}"
        );
        // The delta keeps growing through the slow part and then stays.
        let last = r.splits.last().unwrap();
        assert!((last.cumulative_delta_s - r.delta_s).abs() < 1.0);
    }

    #[test]
    fn faster_than_planned_is_a_negative_delta() {
        let r = review(&trail(4000.0), &run(&[(4000.0, 1.5)], &[]), &plan(1.0)).unwrap();
        assert!(r.delta_s < -1000.0, "{}", r.delta_s);
        assert!(r.best_split.is_some() && r.worst_split.is_none());
    }

    #[test]
    fn stops_are_counted_in_the_split_they_happened_in() {
        let r = review(
            &trail(4000.0),
            &run(&[(4000.0, 1.0)], &[(1250.0, 600.0)]),
            &plan(1.0),
        )
        .unwrap();
        assert!(r.stopped_s > 500.0, "{}", r.stopped_s);
        let with_stop = r.splits.iter().find(|s| s.stopped_s > 300.0).unwrap();
        assert!(
            with_stop.from_m <= 1250.0 && with_stop.to_m >= 1250.0,
            "{with_stop:?}"
        );
        assert!(r.delta_s > 500.0);
    }

    #[test]
    fn an_unfinished_tour_only_compares_what_was_covered() {
        let r = review(&trail(4000.0), &run(&[(1800.0, 1.0)], &[]), &plan(1.0)).unwrap();
        assert!(!r.completed);
        assert!((r.covered_m - 1800.0).abs() < 15.0);
        assert!((r.planned_s - 1800.0).abs() < 20.0);
    }

    #[test]
    fn a_detour_is_off_trail_time_and_does_not_count_as_progress() {
        let mut fixes = run(&[(1000.0, 1.0)], &[]);
        // 3 minutes 100 m to the side, then back.
        let (t_end, d_end) = (fixes.last().unwrap().time_ms.unwrap(), 1000.0);
        let east = 11.0 + 100.0 / (METERS_PER_DEGREE * 46f64.to_radians().cos());
        for k in 1..=36 {
            fixes.push(Fix {
                latitude: north(d_end),
                longitude: east,
                altitude: None,
                time_ms: Some(t_end + k * 5000),
                accuracy: None,
            });
        }
        let t2 = t_end + 36 * 5000;
        for k in 1..=200 {
            fixes.push(Fix {
                latitude: north(d_end + k as f64 * 5.0),
                longitude: 11.0,
                altitude: None,
                time_ms: Some(t2 + k * 5000),
                accuracy: None,
            });
        }
        let r = review(&trail(2000.0), &fixes, &plan(1.0)).unwrap();
        assert!((r.off_trail_s - 175.0).abs() < 15.0, "{}", r.off_trail_s);
        assert!(r.covered_m > 1900.0);
    }

    #[test]
    fn a_profile_plan_beats_a_constant_speed() {
        let profile = Profile {
            step_m: 1000.0,
            total_m: 4000.0,
            seconds: vec![0.0, 1000.0, 3000.0, 4000.0, 5000.0],
        };
        let p = Plan {
            speed_ms: 1.0,
            profile: Some(profile),
        };
        // At plan pace for the profile, the second kilometer takes 2000 s.
        let r = review(
            &trail(4000.0),
            &run(&[(1000.0, 1.0), (1000.0, 0.5), (2000.0, 1.0)], &[]),
            &p,
        )
        .unwrap();
        assert!(r.delta_s.abs() < 40.0, "{}", r.delta_s);
    }

    #[test]
    fn nothing_to_compare_gives_none() {
        assert!(review(&[], &[], &plan(1.0)).is_none());
        assert!(review(&trail(1000.0), &run(&[(10.0, 1.0)], &[]), &plan(1.0)).is_none());
        let untimed: Vec<Fix> = (0..20)
            .map(|i| Fix::at(north(i as f64 * 10.0), 11.0))
            .collect();
        assert!(review(&trail(1000.0), &untimed, &plan(1.0)).is_none());
    }
}

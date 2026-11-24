//! Moving time, stops and the "legs" the pace analysis is built from.
//!
//! A stop is a stay point: the person stayed within [`STOP_RADIUS_M`] of where they were for at
//! least [`MIN_STOP_S`]. Time between fixes that is much longer than the usual interval is a gap
//! (recording paused, GPS lost) and counts as neither moving nor stopped.

use serde::Serialize;

use super::geo::{Fix, cumulative_m, distance_m, smoothed_altitudes};

/// Staying within this of the starting spot counts as standing still.
pub const STOP_RADIUS_M: f64 = 25.0;
/// A pause shorter than this is not a stop (a shoelace, a photo).
pub const MIN_STOP_S: f64 = 120.0;
/// A stop starts and ends where the person was still within this of the middle of it, so the
/// walk in and out of the stay-point radius is not counted as standing still.
const STOP_TRIM_M: f64 = 12.0;
/// A leg is this long at least, so one GPS jitter does not make a steep slope.
pub const LEG_MIN_M: f64 = 30.0;
/// Altitude is averaged over this much track before gradients are taken.
pub const ALTITUDE_WINDOW_M: f64 = 40.0;
const MIN_GAP_S: f64 = 120.0;

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Stop {
    pub latitude: f64,
    pub longitude: f64,
    pub start_ms: Option<i64>,
    pub duration_s: f64,
    /// Distance from the start of the track, in meters.
    pub along_m: f64,
    pub first_index: usize,
    pub last_index: usize,
}

/// A stretch of moving, at least [`LEG_MIN_M`] long: the unit speed and gradient are measured on.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Leg {
    pub start: usize,
    pub end: usize,
    pub along_m: f64,
    pub distance_m: f64,
    pub time_s: f64,
    /// Smoothed altitude change over the leg, when the track has altitude.
    pub rise_m: Option<f64>,
}

impl Leg {
    pub fn speed_ms(&self) -> f64 {
        if self.time_s > 0.0 {
            self.distance_m / self.time_s
        } else {
            0.0
        }
    }

    /// Slope as a fraction (0.1 = 10% uphill), when the altitude is known.
    pub fn grade(&self) -> Option<f64> {
        self.rise_m.map(|r| r / self.distance_m)
    }
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Motion {
    /// False when the track has too few timestamps for anything time-based.
    pub has_time: bool,
    pub distance_m: f64,
    /// First fix to last fix.
    pub elapsed_s: f64,
    pub moving_s: f64,
    pub stopped_s: f64,
    /// Gaps: recording paused or the GPS lost.
    pub paused_s: f64,
    pub moving_distance_m: f64,
    pub avg_moving_speed_ms: Option<f64>,
    pub stops: Vec<Stop>,
    #[serde(skip)]
    pub legs: Vec<Leg>,
}

fn times(fixes: &[Fix]) -> Option<Vec<f64>> {
    let with: usize = fixes.iter().filter(|f| f.time_ms.is_some()).count();
    if fixes.len() < 2 || with * 10 < fixes.len() * 9 {
        return None;
    }
    // Fixes without a time take the previous one, so the interval to them is zero.
    let mut out = Vec::with_capacity(fixes.len());
    let mut last = fixes.iter().find_map(|f| f.time_ms).unwrap_or(0) as f64 / 1000.0;
    for f in fixes {
        if let Some(t) = f.time_ms {
            last = last.max(t as f64 / 1000.0);
        }
        out.push(last);
    }
    Some(out)
}

/// The gap threshold in seconds: much longer than the usual interval between fixes.
pub fn gap_threshold_s(t: &[f64]) -> f64 {
    let mut dts: Vec<f64> = t
        .windows(2)
        .map(|w| w[1] - w[0])
        .filter(|d| *d > 0.0)
        .collect();
    if dts.is_empty() {
        return MIN_GAP_S;
    }
    dts.sort_by(|a, b| a.partial_cmp(b).unwrap());
    (dts[dts.len() / 2] * 6.0).max(MIN_GAP_S)
}

pub fn analyze(fixes: &[Fix]) -> Motion {
    let cum = cumulative_m(fixes);
    let distance_m = cum.last().copied().unwrap_or(0.0);
    let Some(t) = times(fixes) else {
        return Motion {
            has_time: false,
            distance_m,
            elapsed_s: 0.0,
            moving_s: 0.0,
            stopped_s: 0.0,
            paused_s: 0.0,
            moving_distance_m: distance_m,
            avg_moving_speed_ms: None,
            stops: Vec::new(),
            legs: Vec::new(),
        };
    };
    let n = fixes.len();
    let gap_s = gap_threshold_s(&t);

    // Stay points. `stopped[k]` says whether the interval k → k+1 lies inside a stop.
    let mut stopped = vec![false; n.saturating_sub(1)];
    let mut stops = Vec::new();
    let mut i = 0;
    while i + 1 < n {
        let mut j = i + 1;
        while j < n && t[j] - t[j - 1] <= gap_s && distance_m_between(fixes, i, j) <= STOP_RADIUS_M
        {
            j += 1;
        }
        let mut last = j - 1;
        let mut first = i;
        if last > i {
            let mid = (first + last) / 2;
            while last > first && distance_m_between(fixes, mid, last) > STOP_TRIM_M {
                last -= 1;
            }
            while first < last && distance_m_between(fixes, first, mid) > STOP_TRIM_M {
                first += 1;
            }
        }
        let duration = t[last] - t[first];
        if last > first && duration >= MIN_STOP_S {
            for flag in &mut stopped[first..last] {
                *flag = true;
            }
            let count = (last - first + 1) as f64;
            stops.push(Stop {
                latitude: fixes[first..=last].iter().map(|f| f.latitude).sum::<f64>() / count,
                longitude: fixes[first..=last].iter().map(|f| f.longitude).sum::<f64>() / count,
                start_ms: fixes[first].time_ms,
                duration_s: duration,
                along_m: cum[first],
                first_index: first,
                last_index: last,
            });
            i = (j - 1).max(last).max(i + 1);
        } else {
            i += 1;
        }
    }

    let alt = smoothed_altitudes(fixes, &cum, ALTITUDE_WINDOW_M);
    let (mut moving_s, mut stopped_s, mut paused_s, mut moving_distance_m) = (0.0, 0.0, 0.0, 0.0);
    let mut legs = Vec::new();
    // The leg being built from consecutive moving intervals.
    let (mut leg_start, mut leg_dist, mut leg_time) = (0usize, 0.0, 0.0);
    let flush = |end: usize, leg_start: usize, dist: f64, time: f64, legs: &mut Vec<Leg>| {
        if dist >= LEG_MIN_M && time > 0.0 {
            legs.push(Leg {
                start: leg_start,
                end,
                along_m: cum[leg_start],
                distance_m: dist,
                time_s: time,
                rise_m: alt.as_ref().map(|a| a[end] - a[leg_start]),
            });
        }
    };
    for k in 0..n - 1 {
        let dt = t[k + 1] - t[k];
        let d = cum[k + 1] - cum[k];
        if dt > gap_s {
            paused_s += dt;
            flush(k, leg_start, leg_dist, leg_time, &mut legs);
            (leg_start, leg_dist, leg_time) = (k + 1, 0.0, 0.0);
        } else if stopped[k] {
            stopped_s += dt;
            flush(k, leg_start, leg_dist, leg_time, &mut legs);
            (leg_start, leg_dist, leg_time) = (k + 1, 0.0, 0.0);
        } else {
            moving_s += dt;
            moving_distance_m += d;
            if leg_dist == 0.0 && leg_time == 0.0 {
                leg_start = k;
            }
            leg_dist += d;
            leg_time += dt;
            if leg_dist >= LEG_MIN_M {
                flush(k + 1, leg_start, leg_dist, leg_time, &mut legs);
                (leg_start, leg_dist, leg_time) = (k + 1, 0.0, 0.0);
            }
        }
    }
    flush(n - 1, leg_start, leg_dist, leg_time, &mut legs);

    Motion {
        has_time: true,
        distance_m,
        elapsed_s: t[n - 1] - t[0],
        moving_s,
        stopped_s,
        paused_s,
        moving_distance_m,
        avg_moving_speed_ms: if moving_s > 0.0 {
            Some(moving_distance_m / moving_s)
        } else {
            None
        },
        stops,
        legs,
    }
}

fn distance_m_between(fixes: &[Fix], a: usize, b: usize) -> f64 {
    distance_m(&fixes[a], &fixes[b])
}

#[cfg(test)]
mod tests {
    use super::super::geo::test_support::*;
    use super::*;

    /// Walk at 1 m/s for `a` s, stand still for `stop` s, walk again for `b` s.
    fn with_stop(a: i64, stop: i64, b: i64) -> Vec<Fix> {
        let mut fixes = walk(1.0, 5, a, 0);
        let (lat, last_t) = {
            let l = fixes.last().unwrap();
            (l.latitude, l.time_ms.unwrap())
        };
        let mut t = 5;
        while t <= stop {
            fixes.push(Fix {
                latitude: lat,
                longitude: 11.0,
                altitude: None,
                time_ms: Some(last_t + t * 1000),
                accuracy: None,
            });
            t += 5;
        }
        let resume = last_t + stop * 1000;
        for k in 1..=(b / 5) {
            fixes.push(Fix {
                latitude: lat + 5.0 * k as f64 / super::super::geo::METERS_PER_DEGREE,
                longitude: 11.0,
                altitude: None,
                time_ms: Some(resume + k * 5000),
                accuracy: None,
            });
        }
        fixes
    }

    #[test]
    fn steady_walk_is_all_moving() {
        let m = analyze(&walk(1.2, 5, 600, 0));
        assert!(m.has_time);
        assert!((m.elapsed_s - 600.0).abs() < 1e-6);
        assert!((m.moving_s - 600.0).abs() < 1e-6);
        assert_eq!(m.stopped_s, 0.0);
        assert!(m.stops.is_empty());
        assert!((m.avg_moving_speed_ms.unwrap() - 1.2).abs() < 0.01);
    }

    #[test]
    fn a_long_pause_is_a_stop_and_leaves_moving_time_alone() {
        let m = analyze(&with_stop(300, 600, 300));
        assert_eq!(m.stops.len(), 1);
        let stop = &m.stops[0];
        assert!(
            (stop.duration_s - 600.0).abs() < 12.0,
            "{}",
            stop.duration_s
        );
        assert!((stop.along_m - 300.0).abs() < 15.0);
        assert!((m.stopped_s - 600.0).abs() < 12.0);
        assert!((m.moving_s - 600.0).abs() < 12.0, "{}", m.moving_s);
        assert!((m.moving_s + m.stopped_s + m.paused_s - m.elapsed_s).abs() < 1e-6);
    }

    #[test]
    fn a_short_pause_is_not_a_stop() {
        let m = analyze(&with_stop(300, 60, 300));
        assert!(m.stops.is_empty());
        assert_eq!(m.stopped_s, 0.0);
    }

    #[test]
    fn a_gap_in_the_recording_is_paused_not_moving() {
        let mut fixes = walk(1.0, 5, 300, 0);
        let mut later = walk(1.0, 5, 300, 300_000 + 1_800_000);
        for f in &mut later {
            f.latitude += 400.0 / super::super::geo::METERS_PER_DEGREE;
        }
        fixes.extend(later);
        let m = analyze(&fixes);
        assert!((m.paused_s - 1_805.0).abs() < 10.0, "{}", m.paused_s);
        assert!((m.moving_s - 600.0).abs() < 10.0, "{}", m.moving_s);
    }

    #[test]
    fn without_timestamps_only_distance_is_known() {
        let fixes: Vec<Fix> = (0..10)
            .map(|i| Fix::at(north(i as f64 * 10.0), 11.0))
            .collect();
        let m = analyze(&fixes);
        assert!(!m.has_time);
        assert!((m.distance_m - 90.0).abs() < 0.5);
        assert!(m.legs.is_empty());
    }

    #[test]
    fn legs_are_at_least_thirty_meters_and_carry_the_slope() {
        let mut fixes = walk(1.0, 5, 600, 0);
        for (i, f) in fixes.iter_mut().enumerate() {
            f.altitude = Some(500.0 + i as f64 * 0.5); // 5 m per 10 s of 1 m/s: 10% grade
        }
        let m = analyze(&fixes);
        assert!(!m.legs.is_empty());
        assert!(m.legs.iter().all(|l| l.distance_m >= LEG_MIN_M));
        let mid = &m.legs[m.legs.len() / 2];
        assert!(
            (mid.grade().unwrap() - 0.10).abs() < 0.01,
            "{:?}",
            mid.grade()
        );
        assert!((mid.speed_ms() - 1.0).abs() < 0.01);
    }
}

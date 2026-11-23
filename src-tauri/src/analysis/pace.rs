//! Pace against slope: how fast the person really walks (or rides) up, down and across, a
//! personal model built from their own recordings, predictions from it, and fatigue.
//!
//! Slope effects come from Tobler's hiking function for walking and a simple approximation for
//! cycling. They only fill the gaps where the person has no data of their own, and give the
//! "flat-equivalent" speed that makes pace on different terrain comparable.

use serde::{Deserialize, Serialize};

use super::geo::{Activity, Fix, cumulative_m, smoothed_altitudes};
use super::motion::{ALTITUDE_WINDOW_M, Leg, Motion};

/// Width of a slope bin, in percent.
pub const BIN_PCT: f64 = 5.0;
/// Steepest slope with a bin of its own, in percent; steeper legs count in the last bin.
pub const MAX_BIN_PCT: f64 = 30.0;
/// A bin needs this much distance before its speed is trusted over the model.
pub const MIN_BIN_DISTANCE_M: f64 = 200.0;
/// Slower than this is not walking (m/s).
const MIN_MOVING_MS: f64 = 0.3;

/// How much faster (>1) or slower (<1) than on flat ground, at a slope given as a fraction.
pub fn speed_factor(activity: Activity, grade: f64) -> f64 {
    let g = grade.clamp(-0.5, 0.5);
    match activity {
        // Tobler: v = 6 exp(-3.5 |s + 0.05|), relative to the flat value.
        Activity::Foot => (-3.5 * (g + 0.05).abs()).exp() / (-3.5f64 * 0.05).exp(),
        Activity::Bike => {
            if g >= 0.0 {
                1.0 / (1.0 + 14.0 * g)
            } else {
                1.0 + 8.0 * (-g).min(0.1)
            }
        }
    }
}

/// Grade-adjusted speed of a set of legs: Σ(distance / factor) / Σtime.
fn adjusted_speed(activity: Activity, legs: &[&Leg]) -> Option<f64> {
    let time: f64 = legs.iter().map(|l| l.time_s).sum();
    if time <= 0.0 {
        return None;
    }
    let eff: f64 = legs
        .iter()
        .map(|l| l.distance_m / l.grade().map(|g| speed_factor(activity, g)).unwrap_or(1.0))
        .sum();
    Some(eff / time)
}

/// Grade-adjusted moving speed of a whole track, in m/s.
pub fn track_adjusted_speed(activity: Activity, motion: &Motion) -> Option<f64> {
    let legs: Vec<&Leg> = usable_legs(activity, &motion.legs).collect();
    adjusted_speed(activity, &legs)
}

/// Legs that are real movement: not standing around, not a GPS jump.
fn usable_legs<'a>(activity: Activity, legs: &'a [Leg]) -> impl Iterator<Item = &'a Leg> {
    legs.iter()
        .filter(move |l| l.speed_ms() >= MIN_MOVING_MS && l.speed_ms() <= activity.max_speed_ms())
}

fn bin_of(grade: f64) -> usize {
    let pct = (grade * 100.0).clamp(-MAX_BIN_PCT, MAX_BIN_PCT);
    ((pct + MAX_BIN_PCT) / BIN_PCT).round() as usize
}

const BINS: usize = (2.0 * MAX_BIN_PCT / BIN_PCT) as usize + 1;

fn bin_center_pct(i: usize) -> f64 {
    -MAX_BIN_PCT + i as f64 * BIN_PCT
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CurveBin {
    /// Center of the bin, in percent slope (negative is downhill).
    pub grade_pct: f64,
    pub speed_ms: f64,
    /// True when the speed comes from the person's own data, false when it is estimated.
    pub measured: bool,
    /// How far the person went on this slope.
    pub distance_m: f64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PaceModel {
    pub activity: Activity,
    /// Speed on flat ground that matches the person's overall effort.
    pub flat_speed_ms: f64,
    pub bins: Vec<CurveBin>,
    pub legs_used: usize,
    pub distance_m: f64,
}

impl PaceModel {
    /// Expected speed at a slope (fraction), by linear interpolation between bins.
    pub fn speed_at(&self, grade: f64) -> f64 {
        let pct = (grade * 100.0).clamp(-MAX_BIN_PCT, MAX_BIN_PCT);
        let pos = (pct + MAX_BIN_PCT) / BIN_PCT;
        let lo = (pos.floor() as usize).min(self.bins.len() - 1);
        let hi = (lo + 1).min(self.bins.len() - 1);
        let f = pos - lo as f64;
        (self.bins[lo].speed_ms * (1.0 - f) + self.bins[hi].speed_ms * f).max(0.1)
    }
}

/// Collects legs from any number of tracks, then makes the model.
#[derive(Debug, Clone)]
pub struct PaceAccumulator {
    activity: Activity,
    dist: [f64; BINS],
    time: [f64; BINS],
    eff_dist: f64,
    total_time: f64,
    legs: usize,
}

impl PaceAccumulator {
    pub fn new(activity: Activity) -> Self {
        Self {
            activity,
            dist: [0.0; BINS],
            time: [0.0; BINS],
            eff_dist: 0.0,
            total_time: 0.0,
            legs: 0,
        }
    }

    pub fn add(&mut self, motion: &Motion) {
        for leg in usable_legs(self.activity, &motion.legs) {
            let grade = leg.grade();
            let factor = grade.map(|g| speed_factor(self.activity, g)).unwrap_or(1.0);
            self.eff_dist += leg.distance_m / factor;
            self.total_time += leg.time_s;
            self.legs += 1;
            if let Some(g) = grade {
                let b = bin_of(g);
                self.dist[b] += leg.distance_m;
                self.time[b] += leg.time_s;
            }
        }
    }

    pub fn finish(&self) -> PaceModel {
        let flat = if self.total_time > 0.0 && self.eff_dist > 0.0 {
            self.eff_dist / self.total_time
        } else {
            self.activity.default_flat_speed_ms()
        };
        let bins = (0..BINS)
            .map(|i| {
                let center = bin_center_pct(i);
                let measured = self.dist[i] >= MIN_BIN_DISTANCE_M && self.time[i] > 0.0;
                CurveBin {
                    grade_pct: center,
                    speed_ms: if measured {
                        self.dist[i] / self.time[i]
                    } else {
                        flat * speed_factor(self.activity, center / 100.0)
                    },
                    measured,
                    distance_m: self.dist[i],
                }
            })
            .collect();
        PaceModel {
            activity: self.activity,
            flat_speed_ms: flat,
            bins,
            legs_used: self.legs,
            distance_m: self.dist.iter().sum(),
        }
    }
}

/// The pace curve of one track, from its own legs.
pub fn curve_of(activity: Activity, motion: &Motion) -> PaceModel {
    let mut acc = PaceAccumulator::new(activity);
    acc.add(motion);
    acc.finish()
}

/// Predicted time to cover a track, as cumulative seconds at every `step_m` of distance.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Profile {
    pub step_m: f64,
    pub total_m: f64,
    /// `seconds[k]` is the predicted time from the start to `k * step_m`; the last entry is the end.
    pub seconds: Vec<f64>,
}

impl Profile {
    #[cfg(test)]
    pub fn total_s(&self) -> f64 {
        self.seconds.last().copied().unwrap_or(0.0)
    }

    /// Predicted seconds from the start to `along_m`.
    pub fn seconds_at(&self, along_m: f64) -> f64 {
        let along = along_m.clamp(0.0, self.total_m);
        let pos = along / self.step_m;
        let lo = (pos.floor() as usize).min(self.seconds.len() - 1);
        let hi = (lo + 1).min(self.seconds.len() - 1);
        if hi == lo {
            return self.seconds[lo];
        }
        let lo_d = lo as f64 * self.step_m;
        let hi_d = (hi as f64 * self.step_m).min(self.total_m);
        let f = if hi_d > lo_d {
            (along - lo_d) / (hi_d - lo_d)
        } else {
            0.0
        };
        self.seconds[lo] + (self.seconds[hi] - self.seconds[lo]) * f
    }
}

pub fn predict_profile(fixes: &[Fix], model: &PaceModel, step_m: f64) -> Profile {
    let step_m = if step_m.is_finite() && step_m >= 5.0 {
        step_m
    } else {
        50.0
    };
    let cum = cumulative_m(fixes);
    let total = cum.last().copied().unwrap_or(0.0);
    let alt = smoothed_altitudes(fixes, &cum, ALTITUDE_WINDOW_M);
    let alt_at = |d: f64, from: &mut usize| -> f64 {
        let Some(a) = &alt else { return 0.0 };
        while *from + 1 < cum.len() && cum[*from + 1] < d {
            *from += 1;
        }
        let i = (*from).min(cum.len() - 1);
        let j = (i + 1).min(cum.len() - 1);
        let f = if cum[j] > cum[i] {
            ((d - cum[i]) / (cum[j] - cum[i])).clamp(0.0, 1.0)
        } else {
            0.0
        };
        a[i] + (a[j] - a[i]) * f
    };
    let steps = (total / step_m).ceil() as usize;
    let mut seconds = Vec::with_capacity(steps + 1);
    seconds.push(0.0);
    let mut t = 0.0;
    let mut cursor = 0usize;
    let mut prev_d = 0.0;
    let mut prev_alt = alt_at(0.0, &mut cursor);
    for k in 1..=steps {
        let d = (k as f64 * step_m).min(total);
        let a = alt_at(d, &mut cursor);
        let len = d - prev_d;
        let grade = if len > 0.0 { (a - prev_alt) / len } else { 0.0 };
        t += len / model.speed_at(grade);
        seconds.push(t);
        prev_d = d;
        prev_alt = a;
    }
    Profile {
        step_m,
        total_m: total,
        seconds,
    }
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Fatigue {
    /// Moving speed over the first and last third of the distance, m/s.
    pub first_speed_ms: f64,
    pub last_speed_ms: f64,
    /// The same, corrected for slope; what the change in pace is really made of.
    pub first_adjusted_ms: f64,
    pub last_adjusted_ms: f64,
    /// Change of the slope-adjusted pace from the first to the last third, in percent (negative = slower).
    pub change_pct: f64,
    /// False when the track has no altitude, so the adjusted numbers are the plain ones.
    pub grade_adjusted: bool,
}

/// First third against last third of the moving distance. Needs at least 1.5 km of moving.
pub fn fatigue(activity: Activity, motion: &Motion) -> Option<Fatigue> {
    let legs: Vec<&Leg> = usable_legs(activity, &motion.legs).collect();
    let total: f64 = legs.iter().map(|l| l.distance_m).sum();
    if total < 1_500.0 {
        return None;
    }
    let (mut first, mut last): (Vec<&Leg>, Vec<&Leg>) = (Vec::new(), Vec::new());
    let mut run = 0.0;
    for l in &legs {
        let mid = run + l.distance_m / 2.0;
        if mid < total / 3.0 {
            first.push(l);
        } else if mid >= total * 2.0 / 3.0 {
            last.push(l);
        }
        run += l.distance_m;
    }
    let plain = |ls: &[&Leg]| {
        let t: f64 = ls.iter().map(|l| l.time_s).sum();
        if t > 0.0 {
            Some(ls.iter().map(|l| l.distance_m).sum::<f64>() / t)
        } else {
            None
        }
    };
    let (fs, ls_) = (plain(&first)?, plain(&last)?);
    let with_altitude = legs.iter().all(|l| l.rise_m.is_some());
    let (fa, la) = (
        adjusted_speed(activity, &first)?,
        adjusted_speed(activity, &last)?,
    );
    Some(Fatigue {
        first_speed_ms: fs,
        last_speed_ms: ls_,
        first_adjusted_ms: fa,
        last_adjusted_ms: la,
        change_pct: (la / fa - 1.0) * 100.0,
        grade_adjusted: with_altitude,
    })
}

#[cfg(test)]
mod tests {
    use super::super::geo::test_support::*;
    use super::super::motion::analyze;
    use super::*;

    /// A walk north whose speed and slope change per kilometer: (distance_m, speed_ms, grade).
    fn course(parts: &[(f64, f64, f64)]) -> Vec<Fix> {
        let mut fixes = vec![Fix {
            latitude: 46.0,
            longitude: 11.0,
            altitude: Some(1000.0),
            time_ms: Some(0),
            accuracy: None,
        }];
        let (mut d, mut t, mut alt) = (0.0, 0.0, 1000.0);
        for &(len, speed, grade) in parts {
            let steps = (len / 10.0) as usize;
            for _ in 0..steps {
                d += 10.0;
                t += 10.0 / speed;
                alt += 10.0 * grade;
                fixes.push(Fix {
                    latitude: north(d),
                    longitude: 11.0,
                    altitude: Some(alt),
                    time_ms: Some((t * 1000.0) as i64),
                    accuracy: None,
                });
            }
        }
        fixes
    }

    #[test]
    fn walking_is_slower_uphill_and_downhill_than_gentle_down() {
        let f = |g| speed_factor(Activity::Foot, g);
        assert!((f(0.0) - 1.0).abs() < 1e-12);
        assert!(f(0.10) < 0.8);
        assert!(f(-0.05) > 1.1); // Tobler's optimum is a gentle descent
        assert!(f(-0.30) < f(-0.05));
        assert!(f(0.4) < f(0.2));
        assert!(speed_factor(Activity::Bike, -0.05) > 1.0);
        assert!(speed_factor(Activity::Bike, 0.08) < 0.6);
    }

    #[test]
    fn curve_measures_speed_per_slope() {
        // 1 km flat at 1.3 m/s, 1 km at +10% at 0.8 m/s, 1 km at -10% at 1.4 m/s.
        let fixes = course(&[
            (1000.0, 1.3, 0.0),
            (1000.0, 0.8, 0.10),
            (1000.0, 1.4, -0.10),
        ]);
        let model = curve_of(Activity::Foot, &analyze(&fixes));
        let at = |pct: f64| {
            model
                .bins
                .iter()
                .find(|b| (b.grade_pct - pct).abs() < 0.1)
                .unwrap()
        };
        assert!(at(0.0).measured && (at(0.0).speed_ms - 1.3).abs() < 0.05);
        assert!(at(10.0).measured && (at(10.0).speed_ms - 0.8).abs() < 0.05);
        assert!(at(-10.0).measured && (at(-10.0).speed_ms - 1.4).abs() < 0.05);
        // No data at +25%: estimated from the flat speed, and slower than on +10%.
        assert!(!at(25.0).measured);
        assert!(at(25.0).speed_ms < at(10.0).speed_ms);
    }

    #[test]
    fn model_without_data_falls_back_to_defaults() {
        let model = PaceAccumulator::new(Activity::Foot).finish();
        assert!((model.flat_speed_ms - 4_000.0 / 3600.0).abs() < 1e-9);
        assert!(model.bins.iter().all(|b| !b.measured));
        assert_eq!(model.bins.len(), 13);
        assert!(model.speed_at(0.0) > 0.0);
    }

    #[test]
    fn speed_at_interpolates_between_bins() {
        let model = PaceAccumulator::new(Activity::Foot).finish();
        let (a, b) = (model.speed_at(0.0), model.speed_at(0.05));
        let mid = model.speed_at(0.025);
        assert!(mid > a.min(b) - 1e-9 && mid < a.max(b) + 1e-9);
    }

    #[test]
    fn adjusted_speed_is_the_same_on_flat_and_steep_for_the_same_effort() {
        let flat = course(&[(2000.0, 1.2, 0.0)]);
        let steep_speed = 1.2 * speed_factor(Activity::Foot, 0.10);
        let steep = course(&[(2000.0, steep_speed, 0.10)]);
        let a = track_adjusted_speed(Activity::Foot, &analyze(&flat)).unwrap();
        let b = track_adjusted_speed(Activity::Foot, &analyze(&steep)).unwrap();
        assert!((a - b).abs() < 0.03, "{a} vs {b}");
    }

    #[test]
    fn profile_predicts_longer_times_for_steeper_trails() {
        let model = PaceAccumulator::new(Activity::Foot).finish();
        let flat = course(&[(2000.0, 1.0, 0.0)]);
        let hill = course(&[(2000.0, 1.0, 0.10)]);
        let (pf, ph) = (
            predict_profile(&flat, &model, 50.0),
            predict_profile(&hill, &model, 50.0),
        );
        assert!(ph.total_s() > pf.total_s() * 1.2);
        assert!((pf.total_m - 2000.0).abs() < 1.0);
        assert!((pf.total_s() - 2000.0 / model.flat_speed_ms).abs() < 5.0);
        assert!((pf.seconds_at(1000.0) - pf.total_s() / 2.0).abs() < 2.0);
        assert_eq!(pf.seconds_at(-5.0), 0.0);
        assert!((pf.seconds_at(1e9) - pf.total_s()).abs() < 1e-9);
    }

    #[test]
    fn a_model_fitted_to_the_person_predicts_their_own_trail() {
        let fixes = course(&[(1500.0, 1.5, 0.0), (1500.0, 0.7, 0.12)]);
        let motion = analyze(&fixes);
        let model = curve_of(Activity::Foot, &motion);
        let profile = predict_profile(&fixes, &model, 50.0);
        assert!(
            (profile.total_s() - motion.elapsed_s).abs() < motion.elapsed_s * 0.08,
            "{} vs {}",
            profile.total_s(),
            motion.elapsed_s
        );
    }

    #[test]
    fn fatigue_shows_a_slowdown() {
        let fixes = course(&[(1000.0, 1.5, 0.0), (1000.0, 1.3, 0.0), (1000.0, 1.0, 0.0)]);
        let f = fatigue(Activity::Foot, &analyze(&fixes)).unwrap();
        assert!((f.first_speed_ms - 1.5).abs() < 0.05);
        assert!((f.last_speed_ms - 1.0).abs() < 0.05);
        assert!((f.change_pct + 33.3).abs() < 2.0, "{}", f.change_pct);
        assert!(f.grade_adjusted);
    }

    #[test]
    fn fatigue_is_adjusted_for_a_hard_ending() {
        // Last third is uphill and slower, but at the same effort: no real fatigue.
        let up = 1.4 * speed_factor(Activity::Foot, 0.10);
        let fixes = course(&[(1000.0, 1.4, 0.0), (1000.0, 1.4, 0.0), (1000.0, up, 0.10)]);
        let f = fatigue(Activity::Foot, &analyze(&fixes)).unwrap();
        assert!(f.last_speed_ms < f.first_speed_ms - 0.2);
        assert!(f.change_pct.abs() < 4.0, "{}", f.change_pct);
    }

    #[test]
    fn fatigue_needs_enough_distance() {
        assert!(fatigue(Activity::Foot, &analyze(&course(&[(1000.0, 1.2, 0.0)]))).is_none());
    }
}

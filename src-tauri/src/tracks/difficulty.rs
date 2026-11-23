//! A rough difficulty grade for a track, from its length and climb.
//!
//! This is a heuristic, not a standard: it uses "km-effort" (distance plus one km per 100 m
//! of climb), with a bike counting a third of its distance because it covers ground faster.
//! The thresholds are a starting point to tune with real tracks.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Activity {
    Foot,
    Bike,
}

impl Activity {
    pub fn as_str(self) -> &'static str {
        match self {
            Activity::Foot => "foot",
            Activity::Bike => "bike",
        }
    }
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "foot" => Some(Activity::Foot),
            "bike" => Some(Activity::Bike),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Difficulty {
    Easy,
    Moderate,
    Hard,
}

impl Difficulty {
    pub fn as_str(self) -> &'static str {
        match self {
            Difficulty::Easy => "easy",
            Difficulty::Moderate => "moderate",
            Difficulty::Hard => "hard",
        }
    }
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "easy" => Some(Difficulty::Easy),
            "moderate" => Some(Difficulty::Moderate),
            "hard" => Some(Difficulty::Hard),
            _ => None,
        }
    }
}

const MODERATE_FROM: f64 = 8.0;
const HARD_FROM: f64 = 16.0;

/// Effort in "km-effort" units. `gain_m` is `None` for tracks without altitude (climb counts 0).
pub fn effort(activity: Activity, distance_m: f64, gain_m: Option<f64>) -> f64 {
    let km = distance_m.max(0.0) / 1000.0;
    let ground = match activity {
        Activity::Foot => km,
        Activity::Bike => km / 3.0,
    };
    ground + gain_m.unwrap_or(0.0).max(0.0) / 100.0
}

pub fn assess(activity: Activity, distance_m: f64, gain_m: Option<f64>) -> Difficulty {
    let e = effort(activity, distance_m, gain_m);
    if e >= HARD_FROM {
        Difficulty::Hard
    } else if e >= MODERATE_FROM {
        Difficulty::Moderate
    } else {
        Difficulty::Easy
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn short_flat_walk_is_easy_and_long_climb_is_hard() {
        assert_eq!(assess(Activity::Foot, 4_000.0, Some(50.0)), Difficulty::Easy);
        assert_eq!(assess(Activity::Foot, 12_400.0, Some(684.0)), Difficulty::Hard);
        assert_eq!(assess(Activity::Foot, 9_000.0, Some(100.0)), Difficulty::Moderate);
    }

    #[test]
    fn the_same_ground_is_easier_by_bike() {
        assert_eq!(assess(Activity::Foot, 24_000.0, Some(0.0)), Difficulty::Hard);
        assert_eq!(assess(Activity::Bike, 24_000.0, Some(0.0)), Difficulty::Moderate);
    }

    #[test]
    fn missing_altitude_and_nonsense_do_not_panic() {
        assert_eq!(assess(Activity::Foot, 3_000.0, None), Difficulty::Easy);
        assert_eq!(assess(Activity::Foot, -5.0, Some(-10.0)), Difficulty::Easy);
        assert_eq!(assess(Activity::Foot, f64::NAN, None), Difficulty::Easy);
    }

    #[test]
    fn names_round_trip() {
        for d in [Difficulty::Easy, Difficulty::Moderate, Difficulty::Hard] {
            assert_eq!(Difficulty::parse(d.as_str()), Some(d));
        }
        assert_eq!(Activity::parse("walk"), None);
    }
}

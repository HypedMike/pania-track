//! Analysis of recorded tracks: pace, stops, climbs, GPS quality, route matching, heatmap,
//! patterns over time and tour reviews. Everything but `commands` is plain Rust without any
//! framework types, so it is unit tested without a window system.

pub mod climbs;
pub mod geo;
pub mod motion;
pub mod pace;
pub mod patterns;
pub mod quality;
pub mod routes;
pub mod tour_review;

use serde::{Deserialize, Serialize};

use geo::{Activity, Fix};

/// Everything worth saying about one trail.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TrailAnalysis {
    pub motion: motion::Motion,
    /// Slope-adjusted moving speed, m/s.
    pub adjusted_speed_ms: Option<f64>,
    /// Speed against slope, from this trail alone.
    pub curve: pace::PaceModel,
    pub fatigue: Option<pace::Fatigue>,
    pub climbs: Option<climbs::Climbs>,
    pub quality: quality::Quality,
}

pub fn analyze_trail(fixes: &[Fix], activity: Activity) -> TrailAnalysis {
    let fixes = geo::sanitize(fixes);
    let motion = motion::analyze(&fixes);
    TrailAnalysis {
        adjusted_speed_ms: pace::track_adjusted_speed(activity, &motion),
        curve: pace::curve_of(activity, &motion),
        fatigue: pace::fatigue(activity, &motion),
        climbs: climbs::analyze(&fixes, &motion),
        quality: quality::assess(&fixes, activity),
        motion,
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrackInput {
    #[serde(default)]
    pub activity: Activity,
    pub fixes: Vec<Fix>,
}

/// The person's own pace model from any number of recorded tracks of one activity.
pub fn build_pace_model(tracks: &[TrackInput], activity: Activity) -> pace::PaceModel {
    let mut acc = pace::PaceAccumulator::new(activity);
    for t in tracks.iter().filter(|t| t.activity == activity) {
        acc.add(&motion::analyze(&geo::sanitize(&t.fixes)));
    }
    acc.finish()
}

#[cfg(test)]
mod tests {
    use super::geo::test_support::*;
    use super::*;

    #[test]
    fn one_call_analyses_a_trail() {
        let mut fixes = walk(1.2, 5, 1800, 0);
        for (i, f) in fixes.iter_mut().enumerate() {
            f.altitude = Some(1000.0 + (i as f64 * 0.12).min(150.0));
        }
        let a = analyze_trail(&fixes, Activity::Foot);
        assert!(a.motion.has_time && a.motion.stops.is_empty());
        assert!(a.adjusted_speed_ms.unwrap() > 1.0);
        assert!(a.climbs.is_some());
        assert_eq!(a.quality.score, 100);
        // The result serializes camelCase (camelCase, no legs).
        let json = serde_json::to_value(&a).unwrap();
        assert!(json["motion"]["movingS"].is_number());
        assert!(json["motion"].get("legs").is_none());
        assert!(json["curve"]["bins"].is_array());
    }

    #[test]
    fn a_model_from_several_tracks_pools_their_legs_by_activity() {
        let foot = TrackInput {
            activity: Activity::Foot,
            fixes: walk(1.0, 5, 1800, 0),
        };
        let foot2 = TrackInput {
            activity: Activity::Foot,
            fixes: walk(1.4, 5, 1800, 0),
        };
        let bike = TrackInput {
            activity: Activity::Bike,
            fixes: walk(5.0, 5, 1800, 0),
        };
        let model = build_pace_model(&[foot, foot2, bike], Activity::Foot);
        assert!(
            (model.flat_speed_ms - 1.2).abs() < 0.05,
            "{}",
            model.flat_speed_ms
        );
        assert!(model.legs_used > 0);
        assert_eq!(build_pace_model(&[], Activity::Bike).legs_used, 0);
    }

    #[test]
    fn input_types_read_camel_case_json() {
        let fix: Fix =
            serde_json::from_str(r#"{"latitude":46.0,"longitude":11.0,"timeMs":1000}"#).unwrap();
        assert_eq!(fix.time_ms, Some(1000));
        assert!(fix.altitude.is_none() && fix.accuracy.is_none());
        let t: TrackInput = serde_json::from_str(r#"{"activity":"bike","fixes":[]}"#).unwrap();
        assert_eq!(t.activity, Activity::Bike);
        let t: TrackInput = serde_json::from_str(r#"{"fixes":[]}"#).unwrap();
        assert_eq!(t.activity, Activity::Foot);
    }
}

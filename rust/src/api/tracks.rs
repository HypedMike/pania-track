//! GPX and track processing for Dart.

pub use crate::tracks::{
    difficulty::Difficulty,
    gpx::Waypoint,
    simplify::{Options, Point, Report, Simplified},
};
use crate::{
    analysis::geo::Activity,
    tracks::{difficulty, gpx, simplify},
};

/// The points to keep and a report on how faithful the result is.
pub fn simplify_track(points: Vec<Point>, options: Option<Options>) -> Simplified {
    simplify::simplify_with_report(&points, options.unwrap_or_default())
}

/// A rough difficulty grade from length and climb.
#[flutter_rust_bridge::frb(sync)]
pub fn assess_difficulty(activity: Activity, distance_m: f64, gain_m: Option<f64>) -> Difficulty {
    difficulty::assess(activity, distance_m, gain_m)
}

/// A GPX 1.1 document with one track segment, without timestamps.
#[flutter_rust_bridge::frb(sync)]
pub fn write_gpx(name: String, description: String, points: Vec<Point>, waypoints: Vec<Waypoint>) -> String {
    gpx::write_gpx(&name, &description, &points, &waypoints)
}

//! Track analysis for Dart. The heavy ones run on the bridge's worker threads, so the interface
//! stays responsive.

pub use crate::analysis::{
    TrackInput, TrailAnalysis,
    geo::{Activity, Fix},
    pace::{self, PaceModel, Profile},
    patterns::{self, Patterns},
    quality::{self, Cleaned},
    routes::{self, Heatmap, RouteGroup, RouteTrail},
    tour_review::{self, Plan, Review},
};
use crate::analysis;

/// Moving time, stops, pace curve, fatigue, climbs and GPS quality of one trail.
pub fn analyze_trail(fixes: Vec<Fix>, activity: Activity) -> TrailAnalysis {
    analysis::analyze_trail(&fixes, activity)
}

/// The person's own pace model from their recorded trails.
pub fn pace_model(tracks: Vec<TrackInput>, activity: Activity) -> PaceModel {
    analysis::build_pace_model(&tracks, activity)
}

/// Predicted cumulative time along a trail for a pace model; the tour uses it for the arrival time.
pub fn pace_profile(fixes: Vec<Fix>, model: PaceModel, step_m: Option<f64>) -> Profile {
    pace::predict_profile(&analysis::geo::sanitize(&fixes), &model, step_m.unwrap_or(50.0))
}

/// Removes GPS spikes and smooths the altitude; `terrain` (one value per fix) replaces the GPS altitude.
pub fn clean_track(fixes: Vec<Fix>, activity: Activity, terrain: Option<Vec<f64>>) -> Cleaned {
    quality::clean(&fixes, activity, terrain.as_deref())
}

/// Trails that follow the same route, with their times compared.
pub fn group_routes(trails: Vec<RouteTrail>, min_overlap: Option<f64>) -> Vec<RouteGroup> {
    routes::group_routes(&trails, min_overlap.unwrap_or(routes::MIN_OVERLAP))
}

/// How often each part of the map was visited.
pub fn route_heatmap(trails: Vec<RouteTrail>, cell_m: Option<f64>) -> Heatmap {
    routes::heatmap(&trails, cell_m.unwrap_or(200.0))
}

/// When the person goes out, and how the weather affects their pace.
pub fn time_patterns(trails: Vec<patterns::PatternTrail>, tz_offset_min: i32) -> Patterns {
    patterns::analyze_patterns(&trails, tz_offset_min)
}

/// A tour against its plan, kilometer by kilometer.
pub fn review_tour(trail: Vec<Fix>, run: Vec<Fix>, plan: Plan) -> Option<Review> {
    tour_review::review(&trail, &run, &plan)
}

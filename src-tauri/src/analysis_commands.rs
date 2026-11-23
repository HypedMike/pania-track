//! Tauri commands for the track analysis. They only move data in and out; the work is in
//! `analysis`. The heavy ones run on a blocking thread so the interface stays responsive.

use serde::Deserialize;

use crate::analysis::{
    self, TrackInput, TrailAnalysis,
    geo::{Activity, Fix},
    pace::{self, PaceModel, Profile},
    patterns::{self, Patterns},
    quality::{self, Cleaned},
    routes::{self, Heatmap, RouteGroup},
    tour_review::{self, Plan, Review},
};

async fn blocking<T: Send + 'static>(
    work: impl FnOnce() -> T + Send + 'static,
) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(work)
        .await
        .map_err(|e| e.to_string())
}

/// Moving time, stops, pace curve, fatigue, climbs and GPS quality of one trail.
#[tauri::command]
pub async fn analyze_trail(fixes: Vec<Fix>, activity: Activity) -> Result<TrailAnalysis, String> {
    blocking(move || analysis::analyze_trail(&fixes, activity)).await
}

/// The person's own pace model from their recorded trails.
#[tauri::command]
pub async fn pace_model(tracks: Vec<TrackInput>, activity: Activity) -> Result<PaceModel, String> {
    blocking(move || analysis::build_pace_model(&tracks, activity)).await
}

/// Predicted cumulative time along a trail for a pace model; the tour uses it for the arrival time.
#[tauri::command]
pub async fn pace_profile(
    fixes: Vec<Fix>,
    model: PaceModelInput,
    step_m: Option<f64>,
) -> Result<Profile, String> {
    blocking(move || {
        pace::predict_profile(
            &analysis::geo::sanitize(&fixes),
            &model.into_model(),
            step_m.unwrap_or(50.0),
        )
    })
    .await
}

/// A pace model sent back from the frontend: only what predicting needs.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PaceModelInput {
    activity: Activity,
    flat_speed_ms: f64,
    bins: Vec<BinInput>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BinInput {
    grade_pct: f64,
    speed_ms: f64,
    #[serde(default)]
    measured: bool,
    #[serde(default)]
    distance_m: f64,
}

impl PaceModelInput {
    fn into_model(self) -> PaceModel {
        PaceModel {
            activity: self.activity,
            flat_speed_ms: self.flat_speed_ms,
            bins: self
                .bins
                .into_iter()
                .map(|b| pace::CurveBin {
                    grade_pct: b.grade_pct,
                    speed_ms: b.speed_ms,
                    measured: b.measured,
                    distance_m: b.distance_m,
                })
                .collect(),
            legs_used: 0,
            distance_m: 0.0,
        }
    }
}

/// Removes GPS spikes and smooths the altitude; `terrain` (one value per fix) replaces the GPS altitude.
#[tauri::command]
pub async fn clean_track(
    fixes: Vec<Fix>,
    activity: Activity,
    terrain: Option<Vec<f64>>,
) -> Result<Cleaned, String> {
    blocking(move || quality::clean(&fixes, activity, terrain.as_deref())).await
}

/// Trails that follow the same route, with their times compared.
#[tauri::command]
pub async fn group_routes(
    trails: Vec<routes::TrailInput>,
    min_overlap: Option<f64>,
) -> Result<Vec<RouteGroup>, String> {
    blocking(move || routes::group_routes(&trails, min_overlap.unwrap_or(routes::MIN_OVERLAP)))
        .await
}

/// How often each part of the map was visited.
#[tauri::command]
pub async fn route_heatmap(
    trails: Vec<routes::TrailInput>,
    cell_m: Option<f64>,
) -> Result<Heatmap, String> {
    blocking(move || routes::heatmap(&trails, cell_m.unwrap_or(200.0))).await
}

/// When the person goes out, and how the weather affects their pace.
#[tauri::command]
pub async fn time_patterns(
    trails: Vec<patterns::TrailInput>,
    tz_offset_min: i32,
) -> Result<Patterns, String> {
    blocking(move || patterns::analyze_patterns(&trails, tz_offset_min)).await
}

/// A tour against its plan, kilometer by kilometer.
#[tauri::command]
pub async fn review_tour(
    trail: Vec<Fix>,
    run: Vec<Fix>,
    plan: Plan,
) -> Result<Option<Review>, String> {
    blocking(move || tour_review::review(&trail, &run, &plan)).await
}

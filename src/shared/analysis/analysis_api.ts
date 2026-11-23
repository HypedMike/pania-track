import { invoke } from "@tauri-apps/api/core";
import type { GpsCoordinate } from "../../lib/trail/interfaces/gps_coordinate";
import type { TrailActivity } from "../../lib/trail/interfaces/trail";

/**
 * Track analysis. The calculations are done by the Rust backend (`src-tauri/src/analysis`); this
 * file only converts the app's types to what it reads and gives names to what it sends back.
 */

/** A GPS fix as the backend reads it. */
export interface Fix {
  latitude: number;
  longitude: number;
  altitude?: number;
  /** Milliseconds since the epoch. */
  timeMs?: number;
  accuracy?: number;
}

export function toFixes(coords: GpsCoordinate[]): Fix[] {
  return coords.map((c) => {
    const time = c.timestamp ? Date.parse(c.timestamp) : NaN;
    return {
      latitude: c.latitude,
      longitude: c.longitude,
      ...(c.altitude !== undefined && { altitude: c.altitude }),
      ...(!Number.isNaN(time) && { timeMs: time }),
      ...(c.accuracy !== undefined && { accuracy: c.accuracy }),
    };
  });
}

export function fromFixes(fixes: Fix[]): GpsCoordinate[] {
  return fixes.map((f) => ({
    latitude: f.latitude,
    longitude: f.longitude,
    ...(f.altitude !== undefined && { altitude: f.altitude }),
    ...(f.timeMs !== undefined && { timestamp: new Date(f.timeMs).toISOString() }),
    ...(f.accuracy !== undefined && { accuracy: f.accuracy }),
  }));
}

// ── One trail ─────────────────────────────────────────────────────────────────────────────

export interface Stop {
  latitude: number;
  longitude: number;
  startMs?: number;
  durationS: number;
  alongM: number;
  firstIndex: number;
  lastIndex: number;
}

export interface Motion {
  hasTime: boolean;
  distanceM: number;
  elapsedS: number;
  movingS: number;
  stoppedS: number;
  /** Gaps in the recording: paused, or the GPS was lost. */
  pausedS: number;
  movingDistanceM: number;
  avgMovingSpeedMs: number | null;
  stops: Stop[];
}

export interface CurveBin {
  /** Center of the bin, percent slope (negative is downhill). */
  gradePct: number;
  speedMs: number;
  /** From the person's own data (true) or estimated (false). */
  measured: boolean;
  distanceM: number;
}

export interface PaceModel {
  activity: TrailActivity;
  flatSpeedMs: number;
  bins: CurveBin[];
  legsUsed: number;
  distanceM: number;
}

export interface Fatigue {
  firstSpeedMs: number;
  lastSpeedMs: number;
  firstAdjustedMs: number;
  lastAdjustedMs: number;
  /** Negative: slower at the end. */
  changePct: number;
  gradeAdjusted: boolean;
}

export type SegmentKind = "climb" | "descent" | "flat";

export interface Segment {
  kind: SegmentKind;
  startIndex: number;
  endIndex: number;
  startM: number;
  endM: number;
  distanceM: number;
  riseM: number;
  avgGradePct: number;
  durationS: number | null;
  verticalSpeedMh: number | null;
}

export interface Steep {
  startM: number;
  gradePct: number;
  riseM: number;
}

export interface Climbs {
  segments: Segment[];
  totalGainM: number;
  totalLossM: number;
  steepestClimbKm: Steep | null;
  steepestDescentKm: Steep | null;
  avgVerticalSpeedMh: number | null;
}

export type IssueKind = "positionSpike" | "altitudeJump" | "gap";

export interface Issue {
  kind: IssueKind;
  index: number;
  size: number;
}

export interface Quality {
  points: number;
  withAltitudePct: number;
  withTimePct: number;
  accuracy: { medianM: number; p95M: number; poorPct: number } | null;
  spikes: number;
  altitudeJumps: number;
  gaps: number;
  longestGapS: number;
  /** 0–100. */
  score: number;
  suspicious: boolean;
  issues: Issue[];
}

export interface TrailAnalysis {
  motion: Motion;
  adjustedSpeedMs: number | null;
  curve: PaceModel;
  fatigue: Fatigue | null;
  climbs: Climbs | null;
  quality: Quality;
}

export interface CleanedTrack {
  fixes: Fix[];
  removedPoints: number;
  altitudesChanged: number;
  gainBeforeM: number | null;
  gainAfterM: number | null;
}

/** Predicted time along a trail: `seconds[k]` is the time to get to `k * stepM`. */
export interface PaceProfile {
  stepM: number;
  totalM: number;
  seconds: number[];
}

// ── Several trails ────────────────────────────────────────────────────────────────────────

export interface RouteMember {
  id: string;
  reversed: boolean;
  distanceM: number;
  startMs: number | null;
  movingS: number | null;
  elapsedS: number | null;
  adjustedSpeedMs: number | null;
  vsBestPct: number | null;
  isBest: boolean;
}

export interface RouteGroup {
  members: RouteMember[];
  bestId: string | null;
}

export interface Heatmap {
  cellM: number;
  latStep: number;
  lonStep: number;
  cells: { latitude: number; longitude: number; count: number }[];
  maxCount: number;
  trails: number;
  exploredKm2: number;
  /** min lat, min lon, max lat, max lon */
  bounds: [number, number, number, number] | null;
}

export interface Bucket {
  trails: number;
  distanceM: number;
  movingS: number;
  adjustedSpeedMs: number | null;
}

export interface WeatherEffect {
  trails: number;
  tempCorrelation: number | null;
  wetVsDryPct: number | null;
  wetTrails: number;
  bands: { fromC: number | null; toC: number | null; trails: number; adjustedSpeedMs: number | null }[];
}

export interface Patterns {
  trails: number;
  byHour: Bucket[];
  /** Monday first. */
  byWeekday: Bucket[];
  byMonth: Bucket[];
  busiestHour: number | null;
  busiestMonth: number | null;
  fastestHour: number | null;
  fastestMonth: number | null;
  weather: WeatherEffect | null;
}

export interface TourSplit {
  fromM: number;
  toM: number;
  plannedS: number;
  actualS: number;
  /** Positive: slower than planned. */
  deltaS: number;
  cumulativeDeltaS: number;
  stoppedS: number;
}

export interface TourReview {
  completed: boolean;
  trailLengthM: number;
  coveredM: number;
  plannedS: number;
  actualS: number;
  deltaS: number;
  movingS: number;
  stoppedS: number;
  offTrailS: number;
  splits: TourSplit[];
  worstSplit: number | null;
  bestSplit: number | null;
}

export interface TrailForAnalysis {
  id: string;
  activity: TrailActivity;
  coordinates: GpsCoordinate[];
}

const asInput = (t: TrailForAnalysis) => ({ id: t.id, activity: t.activity, fixes: toFixes(t.coordinates) });

export const analysisApi = {
  analyzeTrail: (coords: GpsCoordinate[], activity: TrailActivity) =>
    invoke<TrailAnalysis>("analyze_trail", { fixes: toFixes(coords), activity }),

  /** The person's own speed-against-slope model, from their recorded trails of one activity. */
  paceModel: (trails: TrailForAnalysis[], activity: TrailActivity) =>
    invoke<PaceModel>("pace_model", {
      tracks: trails.filter((t) => t.activity === activity).map((t) => ({ activity: t.activity, fixes: toFixes(t.coordinates) })),
      activity,
    }),

  /** How long each stretch of a trail should take for that model. */
  paceProfile: (coords: GpsCoordinate[], model: PaceModel, stepM = 50) =>
    invoke<PaceProfile>("pace_profile", { fixes: toFixes(coords), model, stepM }),

  /** Removes GPS spikes and smooths the altitude; `terrain` has one elevation per coordinate. */
  cleanTrack: (coords: GpsCoordinate[], activity: TrailActivity, terrain?: number[]) =>
    invoke<CleanedTrack>("clean_track", { fixes: toFixes(coords), activity, terrain: terrain ?? null }),

  groupRoutes: (trails: TrailForAnalysis[]) =>
    invoke<RouteGroup[]>("group_routes", { trails: trails.map(asInput), minOverlap: 0.8 }),

  heatmap: (trails: TrailForAnalysis[], cellM = 200) =>
    invoke<Heatmap>("route_heatmap", { trails: trails.map(asInput), cellM }),

  patterns: (
    trails: (TrailForAnalysis & { weather?: { tempC: number; precipMm: number } | null })[],
    tzOffsetMin = -new Date().getTimezoneOffset(),
  ) =>
    invoke<Patterns>("time_patterns", {
      trails: trails.map((t) => ({ activity: t.activity, fixes: toFixes(t.coordinates), weather: t.weather ?? null })),
      tzOffsetMin,
    }),

  reviewTour: (
    trail: GpsCoordinate[],
    run: Fix[],
    plan: { speedMs: number; profile: PaceProfile | null },
  ) => invoke<TourReview | null>("review_tour", { trail: toFixes(trail), run, plan }),
};

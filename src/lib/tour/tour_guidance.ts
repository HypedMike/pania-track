import { computeStats } from "../../shared/gps/trail_stats";
import type { HourForecast } from "../../shared/weather/open_meteo";
import type { GpsCoordinate } from "../trail/interfaces/gps_coordinate";
import type { TrailActivity, Waypoint } from "../trail/interfaces/trail";
import { isDark, nextSunset } from "./sun";
import {
  bearingDeg,
  nextTurn,
  pointAtDistance,
  projectOnTrack,
  type TrackIndex,
  type Turn,
} from "./track_progress";

// ── Speed and arrival time ────────────────────────────────────────────────────────────────

/** A moment on the trail: when, and how far along it the person was. */
export interface ProgressSample {
  time: number;
  alongM: number;
}

const SPEED_WINDOW_MS = 3 * 60_000;
/** A window shorter than this says little about speed. */
const MIN_WINDOW_MS = 30_000;
/** Below this the person is standing still, and the speed says nothing about the pace. */
const MOVING_MS = 0.5;

export const FOOT_SPEED_MS = 4_000 / 3600;
export const BIKE_SPEED_MS = 14_000 / 3600;
/** Naismith's rule: one extra hour per 600 m of ascent. */
const ASCENT_MS = 600 / 3600;

/** Progress made over the last few minutes, in m/s. Backwards steps count as no progress. */
export function recentSpeedMs(samples: ProgressSample[], nowMs: number): number | null {
  const recent = samples.filter((s) => s.time >= nowMs - SPEED_WINDOW_MS);
  if (recent.length < 2) return null;
  const first = recent[0];
  const last = recent[recent.length - 1];
  const dt = last.time - first.time;
  if (dt < MIN_WINDOW_MS) return null;
  return Math.max(0, last.alongM - first.alongM) / (dt / 1000);
}

/** Progress made since the tour began, in m/s, once there is a minute of it. */
export function averageSpeedMs(first: ProgressSample | null, last: ProgressSample | null): number | null {
  if (!first || !last || last.time - first.time < 60_000) return null;
  return Math.max(0, last.alongM - first.alongM) / ((last.time - first.time) / 1000);
}

/**
 * How fast the trail is expected to be covered, in m/s: the pace it was recorded at when it has
 * timestamps, otherwise walking at 4 km/h (plus Naismith's allowance for climbing) or cycling
 * at 14 km/h.
 */
export function plannedSpeedMs(coords: GpsCoordinate[], activity: TrailActivity): number {
  const stats = computeStats(coords);
  const sane = activity === "bike" ? 12 : 2.5;
  if (stats.durationMs && stats.durationMs > 0 && stats.distanceM > 0) {
    const recorded = stats.distanceM / (stats.durationMs / 1000);
    if (recorded >= 0.3 && recorded <= sane) return recorded;
  }
  if (activity === "bike" || stats.distanceM === 0) return activity === "bike" ? BIKE_SPEED_MS : FOOT_SPEED_MS;
  const seconds = stats.distanceM / FOOT_SPEED_MS + (stats.elevationGainM ?? 0) / ASCENT_MS;
  return stats.distanceM / seconds;
}

/** The speed to base the arrival time on: what the person is doing now, else their average, else the plan. */
export function chooseSpeedMs(live: number | null, average: number | null, planned: number): number {
  if (live !== null && live >= MOVING_MS) return live;
  if (average !== null && average >= MOVING_MS) return average;
  return planned;
}

// ── Guidance ──────────────────────────────────────────────────────────────────────────────

/** Closer than this to the end, the tour counts as arrived. */
export const ARRIVED_M = 30;
/** When off the trail, aim for a point this far ahead of the nearest one, so you rejoin going forward. */
const REJOIN_AHEAD_M = 25;

export interface TourGuidance {
  alongM: number;
  remainingM: number;
  /** 0–100. */
  progressPct: number;
  offTrackM: number;
  /** Closest point of the trail. */
  nearest: { latitude: number; longitude: number };
  /** Compass bearing to head in: along the trail when on it, towards it when off. */
  bearing: number;
  /** The next turn of the trail, when on it. */
  turn: Turn | null;
  nextWaypoint: { name: string; inM: number } | null;
  arrived: boolean;
  /** The speed the arrival time is based on, in m/s. */
  speedMs: number;
  /** Estimated arrival, in milliseconds since the epoch. */
  etaMs: number;
}

export interface GuidanceInput {
  index: TrackIndex;
  waypoints: Waypoint[];
  position: GpsCoordinate;
  /** Progress at the previous fix, to stay on the right lap of loops and out-and-backs. */
  previousAlongM?: number;
  speedMs: number;
  nowMs: number;
  /** Distance beyond which the person counts as off the trail (so turns are not announced). */
  offTrackThresholdM: number;
}

export function computeGuidance(input: GuidanceInput): TourGuidance {
  const { index, position, speedMs, nowMs } = input;
  const projection = projectOnTrack(index, position, input.previousAlongM);
  const alongM = projection.alongM;
  const remainingM = Math.max(0, index.totalM - alongM);
  const offTrack = projection.offTrackM > input.offTrackThresholdM;

  const bearing = offTrack
    ? bearingDeg(position, pointAtDistance(index, alongM + REJOIN_AHEAD_M))
    : bearingDeg(pointAtDistance(index, alongM), pointAtDistance(index, alongM + 30));

  let nextWaypoint: TourGuidance["nextWaypoint"] = null;
  for (const w of input.waypoints) {
    const wAlong = projectOnTrack(index, w).alongM;
    const inM = wAlong - alongM;
    // Waypoints right under the feet are already "reached".
    if (inM > 20 && (!nextWaypoint || inM < nextWaypoint.inM)) nextWaypoint = { name: w.name, inM };
  }

  return {
    alongM,
    remainingM,
    progressPct: index.totalM > 0 ? Math.min(100, (alongM / index.totalM) * 100) : 0,
    offTrackM: projection.offTrackM,
    nearest: projection.nearest,
    bearing,
    turn: offTrack ? null : nextTurn(index, alongM),
    nextWaypoint,
    arrived: remainingM <= ARRIVED_M && !offTrack,
    speedMs,
    etaMs: nowMs + (remainingM / Math.max(speedMs, 0.1)) * 1000,
  };
}

// ── Warnings ──────────────────────────────────────────────────────────────────────────────

export type WarningKind =
  | "offTrack"
  | "noGps"
  | "late"
  | "afterDark"
  | "dark"
  | "storm"
  | "rain"
  | "snow"
  | "wind"
  | "heat"
  | "cold";

export interface TourWarning {
  kind: WarningKind;
  level: "warning" | "danger";
  /** Numbers the message is built from (times in ms since the epoch, speeds in m/s, …). */
  data: Record<string, number>;
}

/** Arriving this much after the wanted time still counts as on time. */
const LATE_GRACE_MS = 5 * 60_000;
/** A GPS signal older than this is reported as lost. */
export const GPS_LOST_MS = 60_000;

const STORM_CODES = new Set([95, 96, 99]);
const isSnow = (code: number) => (code >= 71 && code <= 77) || code === 85 || code === 86;

/** What the forecast says about the hours between `fromMs` and `toMs`. */
export function assessWeather(hours: HourForecast[], fromMs: number, toMs: number): TourWarning[] {
  const window = hours.filter((h) => h.time + 3_600_000 > fromMs && h.time < toMs);
  if (window.length === 0) return [];
  const warnings: TourWarning[] = [];
  // An hour already under way counts from now.
  const at = (pick: (h: HourForecast) => boolean) => Math.max(window.find(pick)?.time ?? 0, fromMs);

  const storm = window.find((h) => STORM_CODES.has(h.code));
  if (storm) warnings.push({ kind: "storm", level: "danger", data: { atMs: Math.max(storm.time, fromMs) } });

  const snow = window.find((h) => isSnow(h.code));
  if (snow) warnings.push({ kind: "snow", level: "warning", data: { atMs: Math.max(snow.time, fromMs) } });

  const wet = window.filter((h) => !isSnow(h.code) && h.precipProbPct >= 60 && h.precipMm >= 0.5);
  if (wet.length > 0 && !storm) {
    const heaviest = wet.reduce((a, b) => (b.precipMm > a.precipMm ? b : a));
    warnings.push({
      kind: "rain",
      level: heaviest.precipMm >= 4 ? "danger" : "warning",
      data: { atMs: Math.max(wet[0].time, fromMs), mm: Math.round(heaviest.precipMm * 10) / 10, probPct: heaviest.precipProbPct },
    });
  }

  const gust = Math.max(...window.map((h) => h.gustKmh));
  if (gust >= 60) {
    warnings.push({
      kind: "wind",
      level: gust >= 90 ? "danger" : "warning",
      data: { atMs: at((h) => h.gustKmh === gust), kmh: Math.round(gust) },
    });
  }

  const hottest = Math.max(...window.map((h) => h.temperatureC));
  if (hottest >= 32) {
    warnings.push({ kind: "heat", level: "warning", data: { atMs: at((h) => h.temperatureC === hottest), c: Math.round(hottest) } });
  }
  const coldest = Math.min(...window.map((h) => h.temperatureC));
  if (coldest <= 0) {
    warnings.push({ kind: "cold", level: "warning", data: { atMs: at((h) => h.temperatureC === coldest), c: Math.round(coldest) } });
  }
  return warnings;
}

export interface WarningInput {
  guidance: TourGuidance;
  /** Whether the person has been off the trail long enough to be told. */
  offTrack: boolean;
  nowMs: number;
  /** Time of the last GPS fix, ms. */
  lastFixMs: number;
  /** The time the person wants to be there by, ms, if they set one. */
  targetArrivalMs: number | null;
  position: GpsCoordinate;
  destination: GpsCoordinate;
  forecast: HourForecast[];
}

/** Everything the person should be warned about right now, most serious first. */
export function computeWarnings(input: WarningInput): TourWarning[] {
  const { guidance, nowMs } = input;
  const warnings: TourWarning[] = [];

  if (input.offTrack) {
    warnings.push({ kind: "offTrack", level: "danger", data: { m: Math.round(guidance.offTrackM) } });
  }
  if (nowMs - input.lastFixMs > GPS_LOST_MS) {
    warnings.push({ kind: "noGps", level: "warning", data: { sinceMs: input.lastFixMs } });
  }
  if (guidance.arrived) return warnings;

  if (input.targetArrivalMs !== null && guidance.etaMs > input.targetArrivalMs + LATE_GRACE_MS) {
    const remainingS = Math.max(1, (input.targetArrivalMs - nowMs) / 1000);
    warnings.push({
      kind: "late",
      level: "warning",
      data: {
        etaMs: guidance.etaMs,
        targetMs: input.targetArrivalMs,
        lateByMs: guidance.etaMs - input.targetArrivalMs,
        // Pace needed to still make it; 0 when the wanted time has already passed.
        neededSpeedMs: input.targetArrivalMs > nowMs ? guidance.remainingM / remainingS : 0,
      },
    });
  }

  const { latitude, longitude } = input.position;
  if (isDark(latitude, longitude, nowMs)) {
    warnings.push({ kind: "dark", level: "warning", data: {} });
  } else {
    const sunset = nextSunset(latitude, longitude, nowMs);
    const dest = input.destination;
    if (sunset !== null && guidance.etaMs > sunset && isDark(dest.latitude, dest.longitude, guidance.etaMs)) {
      warnings.push({
        kind: "afterDark",
        level: guidance.etaMs - sunset > 30 * 60_000 ? "danger" : "warning",
        data: { sunsetMs: sunset, etaMs: guidance.etaMs },
      });
    }
  }

  warnings.push(...assessWeather(input.forecast, nowMs, guidance.etaMs + 30 * 60_000));
  return warnings.sort((a, b) => Number(b.level === "danger") - Number(a.level === "danger"));
}

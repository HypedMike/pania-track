import { haversine } from "../../shared/gps/trail_stats";
import type { GpsCoordinate } from "../trail/interfaces/gps_coordinate";

/** Grade classes used to colour the profile, by absolute grade in percent. */
export const GRADE_STEPS = [8, 15, 25] as const;
export type GradeClass = 0 | 1 | 2 | 3;

export function gradeClass(pct: number): GradeClass {
  const i = GRADE_STEPS.findIndex((step) => Math.abs(pct) < step);
  return (i === -1 ? GRADE_STEPS.length : i) as GradeClass;
}

export interface ProfilePoint {
  /** Distance from the start, in meters. */
  d: number;
  alt: number;
  coordinate: GpsCoordinate;
}

/** A stretch of the profile with one grade, signed (negative = downhill). */
export interface ProfileBin {
  from: number;
  to: number;
  gradePct: number;
}

export interface RouteProfile {
  points: ProfilePoint[];
  bins: ProfileBin[];
  totalM: number;
  minAlt: number;
  maxAlt: number;
}

/** Bins are at least this long: the router's elevation model has ~90 m cells. */
const MIN_BIN_M = 150;
const MAX_BINS = 60;

/** Elevation at distance `d`, interpolated between profile points. */
export function altAt(points: ProfilePoint[], d: number): number {
  let lo = 0;
  let hi = points.length - 1;
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1;
    if (points[mid].d <= d) lo = mid;
    else hi = mid;
  }
  const a = points[lo];
  const b = points[hi];
  if (b.d === a.d) return a.alt;
  return a.alt + ((b.alt - a.alt) * (d - a.d)) / (b.d - a.d);
}

/** Elevation against distance, cut into bins coloured by grade. Null without elevation data. */
export function buildProfile(coordinates: GpsCoordinate[]): RouteProfile | null {
  const points: ProfilePoint[] = [];
  let d = 0;
  for (let i = 0; i < coordinates.length; i++) {
    if (i > 0) d += haversine(coordinates[i - 1], coordinates[i]);
    const alt = coordinates[i].altitude;
    if (alt !== undefined) points.push({ d, alt, coordinate: coordinates[i] });
  }
  if (points.length < 2 || d === 0) return null;

  const totalM = d;
  const binM = Math.max(MIN_BIN_M, totalM / MAX_BINS);
  const count = Math.max(1, Math.round(totalM / binM));
  const bins: ProfileBin[] = [];
  for (let i = 0; i < count; i++) {
    const from = (totalM * i) / count;
    const to = (totalM * (i + 1)) / count;
    bins.push({ from, to, gradePct: ((altAt(points, to) - altAt(points, from)) / (to - from)) * 100 });
  }

  const alts = points.map((p) => p.alt);
  return { points, bins, totalM, minAlt: Math.min(...alts), maxAlt: Math.max(...alts) };
}

/** Profile point closest to distance `d`. */
export function pointAt(profile: RouteProfile, d: number): ProfilePoint {
  let best = profile.points[0];
  for (const p of profile.points) if (Math.abs(p.d - d) < Math.abs(best.d - d)) best = p;
  return best;
}

export function binAt(profile: RouteProfile, d: number): ProfileBin {
  return profile.bins.find((b) => d <= b.to) ?? profile.bins[profile.bins.length - 1];
}

/**
 * Distance along the route at which it passes each checkpoint. Searched in order, so an
 * out-and-back route that passes a spot twice gets the right pass.
 */
export function checkpointDistances(profile: RouteProfile, checkpoints: GpsCoordinate[]): number[] {
  const result: number[] = [];
  let from = 0;
  for (const c of checkpoints) {
    let bestI = from;
    let bestD = Infinity;
    for (let i = from; i < profile.points.length; i++) {
      const dist = haversine(c, profile.points[i].coordinate);
      if (dist < bestD) {
        bestD = dist;
        bestI = i;
      }
    }
    result.push(profile.points[bestI].d);
    from = bestI;
  }
  return result;
}

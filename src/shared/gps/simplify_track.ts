import { invoke } from "@tauri-apps/api/core";
import type { GpsCoordinate } from "../../lib/trail/interfaces/gps_coordinate";

export interface SimplifyOptions {
  /** Largest sideways distance, in meters, the simplified line may be from a dropped point (default 4). */
  toleranceM?: number;
  /** Largest elevation error, in meters, at a dropped point (default 4). */
  altitudeToleranceM?: number;
  /** Points closer than this to the previously kept point count as standing still (default 2). */
  minStepM?: number;
}

/**
 * How much a track was reduced and how faithful the result is to the original. Errors are the
 * sideways distance from every original point to the simplified line.
 */
export interface SimplifyReport {
  originalPoints: number;
  keptPoints: number;
  /** Share of the original points removed, 0–100. */
  removedPct: number;
  toleranceM: number;
  altitudeToleranceM: number;
  minStepM: number;
  maxErrorM: number;
  meanErrorM: number;
  p95ErrorM: number;
  originalDistanceM: number;
  simplifiedDistanceM: number;
  /** Elevation gain, or null when the track has no altitude. */
  originalGainM: number | null;
  simplifiedGainM: number | null;
  maxAltitudeErrorM: number | null;
}

export interface SimplifiedTrack {
  /** The original point objects that were kept, in order; timestamps are untouched. */
  coordinates: GpsCoordinate[];
  report: SimplifyReport;
}

/**
 * Reduces a GPS track to the points that define its shape. The work is done by the Rust
 * backend (`src-tauri/src/simplify.rs`). First and last points are always kept.
 *
 * Every dropped point is within `toleranceM + minStepM` of the simplified line.
 */
export async function simplifyTrack(
  coords: GpsCoordinate[],
  options?: SimplifyOptions,
): Promise<SimplifiedTrack> {
  // Only what the algorithm reads crosses the IPC boundary; timestamps stay here.
  const points = coords.map(({ latitude, longitude, altitude }) => ({ latitude, longitude, altitude }));
  const { kept, report } = await invoke<{ kept: number[]; report: SimplifyReport }>("simplify_track", {
    points,
    options,
  });
  return { coordinates: kept.map((i) => coords[i]), report };
}

/**
 * Nostr tags describing the simplification, so anyone reading a published trail can judge it.
 * Values are strings, as Nostr requires. `distance`/`gain` are the real track's figures;
 * the `simplified_*` ones are what the published line measures.
 */
export function simplificationTags(r: SimplifyReport): string[][] {
  const tags: string[][] = [
    ["original_points", String(r.originalPoints)],
    ["points", String(r.keptPoints)],
    ["removed_pct", String(r.removedPct)],
    ["tolerance_m", String(r.toleranceM)],
    ["error_max_m", String(r.maxErrorM)],
    ["error_p95_m", String(r.p95ErrorM)],
    ["error_mean_m", String(r.meanErrorM)],
    ["distance_m", String(r.originalDistanceM)],
    ["simplified_distance_m", String(r.simplifiedDistanceM)],
  ];
  if (r.originalGainM !== null && r.simplifiedGainM !== null) {
    tags.push(["gain_m", String(r.originalGainM)], ["simplified_gain_m", String(r.simplifiedGainM)]);
  }
  if (r.maxAltitudeErrorM !== null) tags.push(["error_alt_max_m", String(r.maxAltitudeErrorM)]);
  return tags;
}

/**
 * Rounds coordinates for compact storage: 5 decimals of latitude/longitude is about 1 m,
 * altitude to the nearest 0.1 m. Do this after simplifying, not before.
 */
export function roundCoordinates(coords: GpsCoordinate[]): GpsCoordinate[] {
  const r = (v: number, d: number) => Math.round(v * 10 ** d) / 10 ** d;
  return coords.map((c) => ({
    ...c,
    latitude: r(c.latitude, 5),
    longitude: r(c.longitude, 5),
    ...(c.altitude !== undefined && { altitude: r(c.altitude, 1) }),
  }));
}

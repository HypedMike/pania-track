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
 * Reduces a GPS track to the points that define its shape. The work is done by the Rust
 * backend (`src-tauri/src/simplify.rs`); this returns the original point objects that were kept,
 * in order, so timestamps are untouched. First and last points are always kept.
 *
 * Every dropped point is within `toleranceM + minStepM` of the simplified line.
 */
export async function simplifyTrack(
  coords: GpsCoordinate[],
  options?: SimplifyOptions,
): Promise<GpsCoordinate[]> {
  // Only what the algorithm reads crosses the IPC boundary; timestamps stay here.
  const points = coords.map(({ latitude, longitude, altitude }) => ({ latitude, longitude, altitude }));
  const kept = await invoke<number[]>("simplify_track", { points, options });
  return kept.map((i) => coords[i]);
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

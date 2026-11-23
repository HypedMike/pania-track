import type { GpsCoordinate } from "../../lib/trail/interfaces/gps_coordinate";

export interface SimplifyOptions {
  /**
   * Largest sideways distance, in meters, the simplified line may be from any point it drops.
   * Around 3–5 m keeps the shape of a trail on a map; it is about GPS accuracy anyway.
   */
  toleranceM?: number;
  /**
   * Largest elevation error, in meters, at a dropped point. Keeps climbs and descents
   * from being flattened, which would change the elevation gain.
   */
  altitudeToleranceM?: number;
  /** Points closer than this to the previously kept point are treated as standing still. */
  minStepM?: number;
}

export const DEFAULT_SIMPLIFY: Required<SimplifyOptions> = {
  toleranceM: 4,
  altitudeToleranceM: 4,
  minStepM: 2,
};

const EARTH_RADIUS_M = 6_371_000;

interface Projected {
  x: number;
  y: number;
  /** Altitude, or NaN when the point has none. */
  z: number;
}

/** Local flat projection (meters east/north of the first point), accurate enough for a track. */
function project(coords: GpsCoordinate[]): Projected[] {
  const lat0 = (coords[0].latitude * Math.PI) / 180;
  const lon0 = coords[0].longitude;
  const lat0Deg = coords[0].latitude;
  const mPerDeg = (EARTH_RADIUS_M * Math.PI) / 180;
  const cos = Math.cos(lat0);
  return coords.map((c) => ({
    x: (c.longitude - lon0) * mPerDeg * cos,
    y: (c.latitude - lat0Deg) * mPerDeg,
    z: c.altitude ?? NaN,
  }));
}

/**
 * How far point `p` is from the segment `a`–`b`, taking the larger of the sideways distance
 * and the elevation error against the altitude interpolated along the segment.
 * Both are scaled by their tolerance, so a result above 1 means "this point is needed".
 */
function deviation(p: Projected, a: Projected, b: Projected, tolM: number, tolAltM: number): number {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const len2 = dx * dx + dy * dy;
  const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2));
  const side = Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)) / tolM;
  if (Number.isNaN(p.z) || Number.isNaN(a.z) || Number.isNaN(b.z)) return side;
  const vertical = Math.abs(p.z - (a.z + t * (b.z - a.z))) / tolAltM;
  return Math.max(side, vertical);
}

/** Drops points that barely moved since the last kept one; the final point is always kept. */
function dropStationary(coords: GpsCoordinate[], pts: Projected[], minStepM: number) {
  const keep: number[] = [0];
  let last = pts[0];
  for (let i = 1; i < pts.length - 1; i++) {
    if (Math.hypot(pts[i].x - last.x, pts[i].y - last.y) >= minStepM) {
      keep.push(i);
      last = pts[i];
    }
  }
  keep.push(pts.length - 1);
  return { coords: keep.map((i) => coords[i]), pts: keep.map((i) => pts[i]) };
}

/**
 * Reduces a GPS track to the points that define its shape (Ramer–Douglas–Peucker).
 *
 * Standing-still jitter and points along straight stretches go; corners, bends and
 * meaningful elevation changes stay. Kept points are the original ones, untouched
 * (timestamps included), and the first and last are always kept, so distance and duration
 * stay put. Returns a new array and never modifies the input.
 */
export function simplifyTrack(coords: GpsCoordinate[], options: SimplifyOptions = {}): GpsCoordinate[] {
  const { toleranceM, altitudeToleranceM, minStepM } = { ...DEFAULT_SIMPLIFY, ...options };
  const valid = coords.filter((c) => Number.isFinite(c.latitude) && Number.isFinite(c.longitude));
  if (valid.length <= 2) return valid.slice();

  const cleaned = dropStationary(valid, project(valid), minStepM);
  const { pts } = cleaned;
  const n = pts.length;
  if (n <= 2) return cleaned.coords;

  const keep = new Array<boolean>(n).fill(false);
  keep[0] = keep[n - 1] = true;
  // Iterative on purpose: a track of tens of thousands of points would overflow the call stack.
  const stack: [number, number][] = [[0, n - 1]];
  while (stack.length > 0) {
    const [first, last] = stack.pop()!;
    let worst = 0;
    let worstAt = -1;
    for (let i = first + 1; i < last; i++) {
      const d = deviation(pts[i], pts[first], pts[last], toleranceM, altitudeToleranceM);
      if (d > worst) {
        worst = d;
        worstAt = i;
      }
    }
    if (worstAt !== -1 && worst > 1) {
      keep[worstAt] = true;
      stack.push([first, worstAt], [worstAt, last]);
    }
  }
  return cleaned.coords.filter((_, i) => keep[i]);
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

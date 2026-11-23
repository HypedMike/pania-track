import type { GpsCoordinate } from "../trail/interfaces/gps_coordinate";

const EARTH_RADIUS_M = 6_371_000;
const toRad = (deg: number) => (deg * Math.PI) / 180;
const toDeg = (rad: number) => (rad * 180) / Math.PI;

/** A trail prepared for fast "where am I on it" queries. */
export interface TrackIndex {
  coords: GpsCoordinate[];
  /** `cumulativeM[i]` is the distance along the trail from its start to point `i`. */
  cumulativeM: number[];
  totalM: number;
}

type LatLon = Pick<GpsCoordinate, "latitude" | "longitude">;

/** Great-circle distance in meters. */
function distanceM(a: LatLon, b: LatLon): number {
  const dLat = toRad(b.latitude - a.latitude);
  const dLon = toRad(b.longitude - a.longitude);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.latitude)) * Math.cos(toRad(b.latitude)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}

export function buildTrackIndex(coords: GpsCoordinate[]): TrackIndex {
  const cumulativeM = [0];
  for (let i = 1; i < coords.length; i++) {
    cumulativeM.push(cumulativeM[i - 1] + distanceM(coords[i - 1], coords[i]));
  }
  return { coords, cumulativeM, totalM: cumulativeM[cumulativeM.length - 1] ?? 0 };
}

/** Compass bearing from `a` to `b`, in degrees clockwise from north, 0–360. */
export function bearingDeg(a: LatLon, b: LatLon): number {
  const dLon = toRad(b.longitude - a.longitude);
  const y = Math.sin(dLon) * Math.cos(toRad(b.latitude));
  const x =
    Math.cos(toRad(a.latitude)) * Math.sin(toRad(b.latitude)) -
    Math.sin(toRad(a.latitude)) * Math.cos(toRad(b.latitude)) * Math.cos(dLon);
  return (toDeg(Math.atan2(y, x)) + 360) % 360;
}

/** Smallest signed difference `to − from` between two bearings, in (−180, 180]. */
export function bearingDelta(from: number, to: number): number {
  const d = (((to - from) % 360) + 540) % 360 - 180;
  return d === -180 ? 180 : d;
}

/** The point at `distM` along the trail (clamped to its ends). */
export function pointAtDistance(index: TrackIndex, distM: number): LatLon {
  const { coords, cumulativeM, totalM } = index;
  if (coords.length === 0) throw new Error("Empty trail");
  if (distM <= 0) return coords[0];
  if (distM >= totalM) return coords[coords.length - 1];
  let lo = 0;
  let hi = cumulativeM.length - 1;
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1;
    if (cumulativeM[mid] <= distM) lo = mid;
    else hi = mid;
  }
  const span = cumulativeM[hi] - cumulativeM[lo];
  const f = span > 0 ? (distM - cumulativeM[lo]) / span : 0;
  return {
    latitude: coords[lo].latitude + (coords[hi].latitude - coords[lo].latitude) * f,
    longitude: coords[lo].longitude + (coords[hi].longitude - coords[lo].longitude) * f,
  };
}

export interface TrackProjection {
  /** How far the position is from the nearest point of the trail, in meters. */
  offTrackM: number;
  /** Distance from the trail's start to the nearest point, in meters. */
  alongM: number;
  /** The nearest point on the trail. */
  nearest: LatLon;
}

/** Segments this close to the best match all count as "the same place" when choosing among them. */
const AMBIGUITY_M = 15;

/**
 * Finds where on the trail a position is. Loops and out-and-back trails pass the same place more
 * than once; the pass nearest to `previousAlongM` wins, so progress doesn't jump to another lap.
 */
export function projectOnTrack(
  index: TrackIndex,
  position: LatLon,
  previousAlongM?: number,
): TrackProjection {
  const { coords, cumulativeM } = index;
  if (coords.length === 0) throw new Error("Empty trail");
  if (coords.length === 1) {
    return { offTrackM: distanceM(coords[0], position), alongM: 0, nearest: coords[0] };
  }

  // Local flat projection around the position: accurate to well under a meter for the
  // distances that matter here, and much cheaper than great-circle maths per segment.
  const kx = EARTH_RADIUS_M * Math.cos(toRad(position.latitude)) * (Math.PI / 180);
  const ky = EARTH_RADIUS_M * (Math.PI / 180);

  interface Candidate {
    dist: number;
    along: number;
    lat: number;
    lon: number;
  }
  const candidates: Candidate[] = [];
  let best = Infinity;

  for (let i = 0; i < coords.length - 1; i++) {
    const ax = (coords[i].longitude - position.longitude) * kx;
    const ay = (coords[i].latitude - position.latitude) * ky;
    const bx = (coords[i + 1].longitude - position.longitude) * kx;
    const by = (coords[i + 1].latitude - position.latitude) * ky;
    const dx = bx - ax;
    const dy = by - ay;
    const len2 = dx * dx + dy * dy;
    // The position is the origin; project it on the segment.
    const f = len2 > 0 ? Math.max(0, Math.min(1, -(ax * dx + ay * dy) / len2)) : 0;
    const px = ax + dx * f;
    const py = ay + dy * f;
    const dist = Math.hypot(px, py);
    if (dist > best + AMBIGUITY_M) continue;
    if (dist < best) best = dist;
    candidates.push({
      dist,
      along: cumulativeM[i] + (cumulativeM[i + 1] - cumulativeM[i]) * f,
      lat: coords[i].latitude + (coords[i + 1].latitude - coords[i].latitude) * f,
      lon: coords[i].longitude + (coords[i + 1].longitude - coords[i].longitude) * f,
    });
  }

  // Several passes of a loop or out-and-back can be about equally close. Find the pass nearest to
  // where the person was, then take the closest point within that pass. Segments next to each
  // other belong to one pass, and the farther off the trail the more of them are about as close.
  const close = candidates.filter((c) => c.dist <= best + AMBIGUITY_M);
  const passRadius = 1.5 * (best + AMBIGUITY_M) + 50;
  let anchor = close.reduce((a, b) => (b.dist < a.dist ? b : a));
  if (previousAlongM !== undefined) {
    for (const c of close) {
      if (Math.abs(c.along - previousAlongM) < Math.abs(anchor.along - previousAlongM)) anchor = c;
    }
  }
  let pick = anchor;
  for (const c of close) {
    if (Math.abs(c.along - anchor.along) <= passRadius && c.dist < pick.dist) pick = c;
  }
  return {
    offTrackM: pick.dist,
    alongM: pick.along,
    nearest: { latitude: pick.lat, longitude: pick.lon },
  };
}

export interface Turn {
  direction: "left" | "right";
  /** Distance ahead, in meters. */
  inM: number;
  /** True for turns of more than ~120°. */
  sharp: boolean;
}

/** The trail is looked at in chords of this length, which smooths out GPS wobble. */
const CHORD_M = 30;
const TURN_THRESHOLD_DEG = 45;
const SHARP_DEG = 120;

/**
 * The next turn within `lookAheadM`, if any: the first place where the trail's heading has
 * changed by more than 45° from the heading right now.
 */
export function nextTurn(index: TrackIndex, alongM: number, lookAheadM = 300): Turn | null {
  const remaining = index.totalM - alongM;
  if (remaining < CHORD_M * 3) return null;
  const heading = (s: number) =>
    bearingDeg(pointAtDistance(index, s), pointAtDistance(index, s + CHORD_M));
  const reference = heading(alongM);
  const limit = Math.min(lookAheadM, remaining - CHORD_M);
  for (let s = CHORD_M; s <= limit; s += CHORD_M) {
    const delta = bearingDelta(reference, heading(alongM + s));
    if (Math.abs(delta) >= TURN_THRESHOLD_DEG) {
      return { direction: delta > 0 ? "right" : "left", inM: s, sharp: Math.abs(delta) >= SHARP_DEG };
    }
  }
  return null;
}

/** "N", "NE", … for a bearing. */
export function compassPoint(bearing: number): "N" | "NE" | "E" | "SE" | "S" | "SW" | "W" | "NW" {
  const points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"] as const;
  return points[Math.round(bearing / 45) % 8];
}

/** The part of the trail from its start to `alongM`, ending exactly at that point. */
export function trackUpTo(index: TrackIndex, alongM: number): LatLon[] {
  const { coords, cumulativeM } = index;
  if (coords.length === 0 || alongM <= 0) return [];
  const done: LatLon[] = [];
  for (let i = 0; i < coords.length && cumulativeM[i] < alongM; i++) done.push(coords[i]);
  done.push(pointAtDistance(index, alongM));
  return done;
}

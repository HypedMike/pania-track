import { currentLocale } from "../i18n/i18n";
import type { GpsCoordinate } from "../../lib/trail/interfaces/gps_coordinate";

const EARTH_RADIUS_M = 6_371_000;
/** Altitude changes below this are treated as GPS noise when summing elevation gain. */
const ELEVATION_NOISE_M = 3;

function toRad(deg: number): number {
  return (deg * Math.PI) / 180;
}

/** Great-circle distance between two points, in meters. */
export function haversine(a: GpsCoordinate, b: GpsCoordinate): number {
  const dLat = toRad(b.latitude - a.latitude);
  const dLon = toRad(b.longitude - a.longitude);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.latitude)) * Math.cos(toRad(b.latitude)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}

export interface TrailStats {
  distanceM: number;
  elevationGainM: number | null;
  highestM: number | null;
  lowestM: number | null;
  durationMs: number | null;
}

export function computeStats(coords: GpsCoordinate[]): TrailStats {
  let distanceM = 0;
  for (let i = 1; i < coords.length; i++) distanceM += haversine(coords[i - 1], coords[i]);

  const alts = coords.map((c) => c.altitude).filter((a): a is number => a !== undefined);
  let gain = 0;
  let ref = alts[0];
  for (const alt of alts) {
    if (alt - ref >= ELEVATION_NOISE_M) {
      gain += alt - ref;
      ref = alt;
    } else if (ref - alt >= ELEVATION_NOISE_M) {
      ref = alt;
    }
  }

  const times = coords
    .map((c) => (c.timestamp ? Date.parse(c.timestamp) : NaN))
    .filter((t) => !Number.isNaN(t));

  return {
    distanceM,
    elevationGainM: alts.length > 0 ? gain : null,
    highestM: alts.length > 0 ? Math.max(...alts) : null,
    lowestM: alts.length > 0 ? Math.min(...alts) : null,
    durationMs: times.length > 1 ? times[times.length - 1] - times[0] : null,
  };
}

export function formatDistance(m: number): string {
  return m < 1000 ? `${Math.round(m)} m` : `${(m / 1000).toFixed(1)} km`;
}

export function formatElevation(m: number | null, signed = false): string {
  if (m === null) return "—";
  return `${signed && m > 0 ? "+" : ""}${Math.round(m)} m`;
}

export function formatDuration(ms: number | null): string {
  if (ms === null) return "—";
  const totalMin = Math.round(ms / 60_000);
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  return h > 0 ? `${h}h ${m.toString().padStart(2, "0")}m` : `${m}m`;
}

export function formatDate(ms?: number): string {
  if (!ms) return "";
  return new Date(ms).toLocaleDateString(currentLocale(), { month: "short", day: "numeric" });
}

/** Average pace as "m:ss /km", or "—" when there is no distance yet. */
export function formatPace(distanceM: number, movingMs: number): string {
  if (distanceM < 50) return "—";
  const secPerKm = movingMs / 1000 / (distanceM / 1000);
  const m = Math.floor(secPerKm / 60);
  const s = Math.round(secPerKm % 60);
  return `${m}:${(s === 60 ? 0 : s).toString().padStart(2, "0")} /km`;
}

/** Clock-style duration, "hh:mm:ss". */
export function formatClock(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const pad = (n: number) => n.toString().padStart(2, "0");
  return `${pad(Math.floor(total / 3600))}:${pad(Math.floor((total % 3600) / 60))}:${pad(total % 60)}`;
}

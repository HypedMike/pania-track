import type { GpsCoordinate } from "../trail/interfaces/gps_coordinate";

/** Degrees of latitude per meter. */
export const M = 1 / 111_195;
const BASE_LAT = 46;
const BASE_LON = 11;
const KX = M / Math.cos((BASE_LAT * Math.PI) / 180);

/** A point `northM` north and `eastM` east of the test origin. */
export function at(northM: number, eastM = 0): GpsCoordinate {
  return { latitude: BASE_LAT + northM * M, longitude: BASE_LON + eastM * KX };
}

/** A polyline through the given (north, east) corners, with a point every 10 m. */
export function line(...corners: [number, number][]): GpsCoordinate[] {
  const out: GpsCoordinate[] = [];
  for (let c = 0; c < corners.length - 1; c++) {
    const [n0, e0] = corners[c];
    const [n1, e1] = corners[c + 1];
    const len = Math.hypot(n1 - n0, e1 - e0);
    const steps = Math.max(1, Math.round(len / 10));
    for (let i = c === 0 ? 0 : 1; i <= steps; i++) {
      out.push(at(n0 + ((n1 - n0) * i) / steps, e0 + ((e1 - e0) * i) / steps));
    }
  }
  return out;
}

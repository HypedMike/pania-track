export interface GpsCoordinate {
  latitude: number;
  longitude: number;
  /** Elevation in meters above sea level. */
  altitude?: number;
  /** Time the point was recorded, as an ISO 8601 string. */
  timestamp?: string;
}

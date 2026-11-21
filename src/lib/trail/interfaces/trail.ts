import { GpsCoordinate } from "./gps_coordinate";

export type TrailSource = "recorded" | "imported";

/** A named point of interest along a trail. */
export interface Waypoint extends GpsCoordinate {
  name: string;
}

export interface Trail {
  id: string;
  name: string;
  description?: string;
  source: TrailSource;
  /** Ordered points that make up the trail path. */
  coordinates: GpsCoordinate[];
  waypoints: Waypoint[];
  /** Creation time, in milliseconds since the epoch. */
  createdAt?: number;
  updatedAt?: number;
}

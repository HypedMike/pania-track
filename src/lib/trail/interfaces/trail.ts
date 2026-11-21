import { GpsCoordinate } from "./gps_coordinate";

export interface Trail {
  id: string;
  name: string;
  description?: string;
  /** Ordered points that make up the trail path. */
  coordinates: GpsCoordinate[];
  createdAt?: number;
  updatedAt?: number;
}

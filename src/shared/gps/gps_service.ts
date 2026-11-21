import {
  checkPermissions,
  getCurrentPosition as getNativePosition,
  requestPermissions,
} from "@tauri-apps/plugin-geolocation";
import type { GpsCoordinate } from "../../lib/trail/interfaces/gps_coordinate";

const isMobile = /android|iphone|ipad/i.test(navigator.userAgent);

async function ensureNativePermission(): Promise<void> {
  let status = await checkPermissions();
  if (status.location !== "granted") {
    status = await requestPermissions(["location"]);
  }
  if (status.location !== "granted") {
    throw new Error("Location permission was denied.");
  }
}

function getBrowserPosition(): Promise<GpsCoordinate> {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(new Error("Geolocation is not available on this device."));
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (p) =>
        resolve({
          latitude: p.coords.latitude,
          longitude: p.coords.longitude,
          ...(p.coords.altitude !== null && { altitude: p.coords.altitude }),
          timestamp: new Date(p.timestamp).toISOString(),
        }),
      (e) => reject(new Error(e.message)),
      { enableHighAccuracy: true, timeout: 20_000 },
    );
  });
}

export const gpsService = {
  /** Asks for location permission if needed. Throws if it is denied. */
  async ensurePermission(): Promise<void> {
    if (isMobile) await ensureNativePermission();
  },

  /** Reads the current GPS position. The native plugin is used on mobile, the browser API on desktop. */
  async getCurrentPosition(): Promise<GpsCoordinate> {
    if (!isMobile) return getBrowserPosition();
    const p = await getNativePosition({ enableHighAccuracy: true, timeout: 20_000, maximumAge: 0 });
    return {
      latitude: p.coords.latitude,
      longitude: p.coords.longitude,
      ...(p.coords.altitude != null && { altitude: p.coords.altitude }),
      timestamp: new Date(p.timestamp).toISOString(),
    };
  },
};

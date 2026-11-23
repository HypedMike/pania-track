import { invoke } from "@tauri-apps/api/core";
import type { GpsFix } from "./gps_service";

interface NativePoint {
  latitude: number;
  longitude: number;
  altitude: number | null;
  accuracy: number | null;
  time: number;
}

interface TakeResult {
  points: NativePoint[];
  running: boolean;
  error: string | null;
}

/** What the native service needs to alert on its own when the person leaves a trail. */
export interface OffTrackGuard {
  /** Farther than this from the trail counts as off it. */
  thresholdM: number;
  /** The trail as [latitude, longitude] pairs. */
  track: [number, number][];
  /** Notification texts, already translated; `{m}` in `text` becomes the distance. */
  title: string;
  text: string;
}

function toFix(p: NativePoint): GpsFix {
  return {
    latitude: p.latitude,
    longitude: p.longitude,
    ...(p.altitude !== null && { altitude: p.altitude }),
    ...(p.accuracy !== null && { accuracy: p.accuracy }),
    timestamp: new Date(p.time).toISOString(),
  };
}

/**
 * The native trail-recorder plugin: an Android foreground service that keeps collecting GPS
 * points with the screen off. Points are buffered natively until `takePoints` collects them.
 */
export const backgroundRecorder = {
  /** Only Android has the native service; elsewhere the app polls the position itself. */
  supported: /android/i.test(navigator.userAgent),

  /**
   * Starts the service. With `offTrackGuard` it also watches the fixes against a trail and raises
   * a notification by itself when the person strays, which keeps working with the screen off.
   */
  async start(intervalMs: number, offTrackGuard?: OffTrackGuard): Promise<void> {
    // The notification permission only affects whether the status notification is visible.
    await invoke("plugin:trail-recorder|request_permissions").catch(() => undefined);
    await invoke("plugin:trail-recorder|start", {
      options: { intervalMs, guardJson: offTrackGuard ? JSON.stringify(offTrackGuard) : null },
    });
  },

  async stop(): Promise<void> {
    await invoke("plugin:trail-recorder|stop");
  },

  /** Returns, and removes from the native buffer, the points recorded since the last call. */
  async takePoints(): Promise<{ points: GpsFix[]; running: boolean; error: string | null }> {
    const result = await invoke<TakeResult>("plugin:trail-recorder|take_points");
    return { ...result, points: result.points.map(toFix) };
  },
};

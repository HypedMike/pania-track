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

/**
 * What the native side needs to show live stats in the status notification, the Android 16 Live
 * Update and the widget. It computes the numbers itself from the GPS fixes, so they keep updating
 * with the screen off.
 */
export interface LiveInfo {
  mode: "recording" | "tour";
  /** Notification and widget title: "Recording trail" or the name of the trail being followed. */
  title: string;
  /** Translated captions. */
  labels: { distance: string; time: string; climb: string; left: string; arrival: string; done: string };
  /** What a resumed recording already has, so the numbers carry on instead of restarting. */
  baseDistanceM: number;
  baseAscentM: number;
  baseElapsedMs: number;
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
  async start(intervalMs: number, offTrackGuard?: OffTrackGuard, live?: LiveInfo): Promise<void> {
    // The notification permission only affects whether the status notification is visible.
    await invoke("plugin:trail-recorder|request_permissions").catch(() => undefined);
    await invoke("plugin:trail-recorder|start", {
      options: {
        intervalMs,
        guardJson: offTrackGuard ? JSON.stringify(offTrackGuard) : null,
        liveJson: live ? JSON.stringify(live) : null,
      },
    });
  },

  async stop(): Promise<void> {
    await invoke("plugin:trail-recorder|stop");
  },

  /** Whether Live Updates exist on this phone (Android 16+) and are turned on for the app. */
  async liveUpdateStatus(): Promise<{ supported: boolean; enabled: boolean }> {
    if (!this.supported) return { supported: false, enabled: false };
    try {
      return await invoke("plugin:trail-recorder|live_update_status");
    } catch {
      return { supported: false, enabled: false };
    }
  },

  /** Opens the system screen where the person can turn Live Updates on. */
  async openLiveUpdateSettings(): Promise<void> {
    await invoke("plugin:trail-recorder|open_live_update_settings");
  },

  /** Returns, and removes from the native buffer, the points recorded since the last call. */
  async takePoints(): Promise<{ points: GpsFix[]; running: boolean; error: string | null }> {
    const result = await invoke<TakeResult>("plugin:trail-recorder|take_points");
    return { ...result, points: result.points.map(toFix) };
  },
};

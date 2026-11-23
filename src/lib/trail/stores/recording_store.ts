import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";
import { t } from "../../../shared/i18n/i18n";
import { backgroundRecorder, type LiveInfo } from "../../../shared/gps/background_recorder";
import { liveLabels } from "../../../shared/gps/live_info";
import { computeStats } from "../../../shared/gps/trail_stats";
import { captureLock } from "../../../shared/gps/capture_lock";
import { gpsService, type GpsFix } from "../../../shared/gps/gps_service";
import { recordIntervalMs } from "../../../shared/settings/settings_store";
import type { GpsCoordinate } from "../interfaces/gps_coordinate";
import type { Waypoint } from "../interfaces/trail";

/** How often the webview collects points from the native service while visible. */
const DRAIN_INTERVAL_MS = 1_000;

type Status = "idle" | "recording" | "paused";

interface RecordingState {
  status: Status;
  points: GpsCoordinate[];
  waypoints: Waypoint[];
  /** Wall-clock time the recording began, in ms. */
  startedAt: number | null;
  /** Active time accumulated before the current run, in ms (pauses excluded). */
  accumulatedMs: number;
  /** When the current run started, or null while paused. */
  resumedAt: number | null;
  /** Latest GPS reading, whether or not it was added to the track. */
  current: GpsFix | null;
  error: string | null;

  start: () => Promise<void>;
  pause: () => Promise<void>;
  resume: () => Promise<void>;
  addWaypoint: () => Promise<void>;
  /** Clears everything and stops capturing. */
  discard: () => Promise<void>;
  /** Active recording time in ms, excluding pauses. */
  elapsedMs: () => number;
  /** Picks a restored session back up after the webview was recreated. */
  reattach: () => Promise<void>;
}

const INITIAL = {
  status: "idle" as Status,
  points: [] as GpsCoordinate[],
  waypoints: [] as Waypoint[],
  startedAt: null,
  accumulatedMs: 0,
  resumedAt: null,
  current: null,
  error: null,
};

function message(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/** A track point keeps its GPS accuracy (rounded), so the recording's quality can be judged later. */
function toTrackPoint(fix: GpsFix): GpsCoordinate {
  return fix.accuracy === undefined ? fix : { ...fix, accuracy: Math.round(fix.accuracy * 10) / 10 };
}

function stripAccuracy({ accuracy: _accuracy, ...point }: GpsFix): GpsCoordinate {
  return point;
}

let timer: ReturnType<typeof setInterval> | null = null;
let busy = false;
let starting = false;

function stopTimer() {
  if (timer) clearInterval(timer);
  timer = null;
}

/** Live stats context for the native notification and widget; a resumed recording carries on from what it has. */
function liveInfo(state: { points: GpsCoordinate[]; accumulatedMs: number; resumedAt: number | null }): LiveInfo {
  const stats = computeStats(state.points);
  return {
    mode: "recording",
    title: t("live.recording"),
    labels: liveLabels(),
    baseDistanceM: stats.distanceM,
    baseAscentM: stats.elevationGainM ?? 0,
    baseElapsedMs: state.accumulatedMs + (state.resumedAt ? Date.now() - state.resumedAt : 0),
  };
}

export const useRecordingStore = create<RecordingState>()(
  persist(
    (set, get) => {
      /** Adds fixes to the track; fixes that arrive while paused only update the live position. */
      function addFixes(fixes: GpsFix[], keep: boolean) {
        if (fixes.length === 0) return;
        set((s) => ({
          current: fixes[fixes.length - 1],
          points: keep ? [...s.points, ...fixes.map(toTrackPoint)] : s.points,
        }));
      }

      /** Collects what the native service buffered. Points recorded before a pause are kept. */
      async function drainNative() {
        if (busy) return;
        busy = true;
        try {
          const { points, running, error } = await backgroundRecorder.takePoints();
          addFixes(points, get().status !== "idle");
          if (error) set({ error });
          else if (points.length > 0) set({ error: null });
          // The service is gone while we think we're recording (e.g. the system stopped it).
          if (!running && get().status === "recording" && !error) {
            await backgroundRecorder.start(recordIntervalMs(), undefined, liveInfo(get()));
          }
        } catch (e) {
          set({ error: message(e) });
        } finally {
          busy = false;
        }
      }

      /** Foreground-only fallback used where the native service is unavailable. */
      async function pollPosition() {
        if (busy || get().status !== "recording") return;
        busy = true;
        try {
          const fix = await gpsService.getCurrentPosition();
          addFixes([fix], get().status === "recording");
          set({ error: null });
        } catch (e) {
          set({ error: message(e) });
        } finally {
          busy = false;
        }
      }

      function startTimer() {
        stopTimer();
        const tick = backgroundRecorder.supported ? drainNative : pollPosition;
        void tick();
        timer = setInterval(
          () => void tick(),
          backgroundRecorder.supported ? DRAIN_INTERVAL_MS : recordIntervalMs(),
        );
      }

      async function beginCapture() {
        if (backgroundRecorder.supported) await backgroundRecorder.start(recordIntervalMs(), undefined, liveInfo(get()));
        startTimer();
      }

      async function endCapture() {
        stopTimer();
        if (!backgroundRecorder.supported) return;
        await backgroundRecorder.stop().catch(() => undefined);
        await drainNative();
      }

      return {
        ...INITIAL,

        start: async () => {
          if (get().status !== "idle" || starting) return;
          if (!captureLock.claim("recording")) {
            set({ error: t("error.tourActive") });
            return;
          }
          starting = true;
          set({ error: null });
          try {
            await gpsService.ensurePermission();
            // Drop anything left in the native buffer by an earlier, abandoned session.
            if (backgroundRecorder.supported) await backgroundRecorder.takePoints().catch(() => undefined);
            const now = Date.now();
            set({ ...INITIAL, status: "recording", startedAt: now, resumedAt: now });
            await beginCapture();
          } catch (e) {
            stopTimer();
            captureLock.release("recording");
            set({ ...INITIAL, error: message(e) });
          } finally {
            starting = false;
          }
        },

        pause: async () => {
          if (get().status !== "recording") return;
          set((s) => ({
            status: "paused",
            accumulatedMs: s.accumulatedMs + (s.resumedAt ? Date.now() - s.resumedAt : 0),
            resumedAt: null,
          }));
          await endCapture();
        },

        resume: async () => {
          if (get().status !== "paused") return;
          set({ status: "recording", resumedAt: Date.now(), error: null });
          try {
            await beginCapture();
          } catch (e) {
            set({ error: message(e) });
          }
        },

        addWaypoint: async () => {
          try {
            const point = stripAccuracy(get().current ?? (await gpsService.getCurrentPosition()));
            set((s) => ({
              waypoints: [...s.waypoints, { ...point, name: `Waypoint ${s.waypoints.length + 1}` }],
            }));
          } catch (e) {
            set({ error: message(e) });
          }
        },

        discard: async () => {
          stopTimer();
          captureLock.release("recording");
          set({ ...INITIAL });
          if (backgroundRecorder.supported) {
            await backgroundRecorder.stop().catch(() => undefined);
            await backgroundRecorder.takePoints().catch(() => undefined);
          }
        },

        elapsedMs: () => {
          const { accumulatedMs, resumedAt } = get();
          return accumulatedMs + (resumedAt ? Date.now() - resumedAt : 0);
        },

        reattach: async () => {
          const { status } = get();
          captureLock.claim("recording");
          try {
            if (status === "recording") await beginCapture();
            // Collect points the service recorded before it was paused.
            else if (status === "paused" && backgroundRecorder.supported) await drainNative();
          } catch (e) {
            set({ error: message(e) });
          }
        },
      };
    },
    {
      // Keeps the session if the webview is recreated (app swiped away, process restarted)
      // while the native service carries on recording.
      name: "pania.recording",
      storage: createJSONStorage(() => localStorage),
      partialize: ({ status, points, waypoints, startedAt, accumulatedMs, resumedAt }) => ({
        status,
        points,
        waypoints,
        startedAt,
        accumulatedMs,
        resumedAt,
      }),
      onRehydrateStorage: () => (state) => {
        if (state && state.status !== "idle") void state.reattach();
      },
    },
  ),
);

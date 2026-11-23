import { toast } from "sonner";
import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";
import { backgroundRecorder, type OffTrackGuard } from "../../shared/gps/background_recorder";
import { captureLock } from "../../shared/gps/capture_lock";
import { gpsService, type GpsFix } from "../../shared/gps/gps_service";
import { simplifyTrack } from "../../shared/gps/simplify_track";
import { t } from "../../shared/i18n/i18n";
import { notifyLocal, prepareLocalNotifications } from "../../shared/notify/local_notification";
import { useSettingsStore } from "../../shared/settings/settings_store";
import { fetchForecast, type HourForecast } from "../../shared/weather/open_meteo";
import { trailRepository } from "../trail/repositories/trail_repository";
import type { Trail } from "../trail/interfaces/trail";
import { OffTrackMonitor } from "./off_track_monitor";
import {
  averageSpeedMs,
  chooseSpeedMs,
  computeGuidance,
  computeWarnings,
  plannedSpeedMs,
  recentSpeedMs,
  type ProgressSample,
  type TourGuidance,
  type TourWarning,
} from "./tour_guidance";
import { buildTrackIndex, pointAtDistance, projectOnTrack, type TrackIndex } from "./track_progress";
import { warningText } from "./warning_text";

/** Time between GPS fixes during a tour: quick enough for directions, easy on the battery. */
const TOUR_INTERVAL_MS = 3_000;
/** How often the webview collects points from the native service while visible. */
const DRAIN_INTERVAL_MS = 1_000;
/** The forecast is fetched again after this long, or when the rest of the trail is far from where it was fetched. */
const FORECAST_MAX_AGE_MS = 30 * 60_000;
const FORECAST_RETRY_MS = 5 * 60_000;
const FORECAST_MOVE_M = 5_000;
/** Fixes older than this update the state but no longer raise alerts in the app. */
const STALE_FIX_MS = 30_000;
/** A warning that goes away and comes back within this time is not announced again. */
const ANNOUNCE_COOLDOWN_MS = 10 * 60_000;
/** Points sent to the native off-track guard are thinned to within this many meters of the trail. */
const GUARD_TOLERANCE_M = 5;
const GUARD_MAX_POINTS = 4_000;

type Status = "idle" | "active";

interface TourState {
  status: Status;
  trailId: string | null;
  /** The trail being followed. Loaded again from the database after the webview was recreated. */
  trail: Trail | null;
  startedAt: number | null;
  /** The time the person wants to arrive by, ms since the epoch. */
  targetArrivalMs: number | null;

  /** Latest GPS reading. */
  current: GpsFix | null;
  /** Time of the latest fix, ms since the epoch. */
  lastFixMs: number | null;
  guidance: TourGuidance | null;
  /** Speed over the last few minutes, m/s (null until there is enough to tell). */
  liveSpeedMs: number | null;
  offTrack: boolean;
  warnings: TourWarning[];
  error: string | null;

  start: (trail: Trail, targetArrivalMs: number | null) => Promise<void>;
  /** Ends the tour and stops GPS capture. */
  stop: () => Promise<void>;
  /** Picks a restored tour back up after the webview was recreated. */
  reattach: () => Promise<void>;
}

const INITIAL = {
  status: "idle" as Status,
  trailId: null,
  trail: null,
  startedAt: null,
  targetArrivalMs: null,
  current: null,
  lastFixMs: null,
  guidance: null,
  liveSpeedMs: null,
  offTrack: false,
  warnings: [] as TourWarning[],
  error: null,
};

function message(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

// Working state that does not need to render anything, so it lives outside the store.
let timer: ReturnType<typeof setInterval> | null = null;
let busy = false;
let starting = false;
let index: TrackIndex | null = null;
let guardTrack: [number, number][] = [];
let plannedMs = 0;
let samples: ProgressSample[] = [];
let firstSample: ProgressSample | null = null;
let lastAlongM: number | undefined;
const monitor = new OffTrackMonitor();
let forecast: HourForecast[] = [];
let forecastAt = 0;
let forecastFrom: { latitude: number; longitude: number } | null = null;
let forecastFetching = false;
const announced = new Map<string, number>();
let arrivedAnnounced = false;

function stopTimer() {
  if (timer) clearInterval(timer);
  timer = null;
}

function resetWorkingState() {
  index = null;
  guardTrack = [];
  samples = [];
  firstSample = null;
  lastAlongM = undefined;
  monitor.reset();
  forecast = [];
  forecastAt = 0;
  forecastFrom = null;
  announced.clear();
  arrivedAnnounced = false;
}

/** The trail as the native service needs it: thinned out, as [latitude, longitude] pairs. */
async function prepareGuardTrack(trail: Trail): Promise<[number, number][]> {
  let coords = trail.coordinates;
  try {
    coords = (await simplifyTrack(coords, { toleranceM: GUARD_TOLERANCE_M })).coordinates;
  } catch {
    // Without the Rust backend (plain browser) fall through to simple thinning.
  }
  if (coords.length > GUARD_MAX_POINTS) {
    const step = Math.ceil(coords.length / GUARD_MAX_POINTS);
    coords = coords.filter((_, i) => i % step === 0 || i === coords.length - 1);
  }
  return coords.map((c) => [c.latitude, c.longitude]);
}

function offTrackGuard(): OffTrackGuard {
  return {
    thresholdM: useSettingsStore.getState().offTrackM,
    track: guardTrack,
    title: t("tour.alert.title"),
    text: t("tour.alert.text", { m: "{m}" }),
  };
}

export const useTourStore = create<TourState>()(
  persist(
    (set, get) => {
      function setupTrail(trail: Trail) {
        resetWorkingState();
        index = buildTrackIndex(trail.coordinates);
        plannedMs = plannedSpeedMs(trail.coordinates, trail.activity);
      }

      /** Takes in the GPS fixes in order, then recomputes what the person sees. */
      function ingest(fixes: GpsFix[]) {
        const trail = get().trail;
        if (!trail || !index || fixes.length === 0) return;
        const threshold = useSettingsStore.getState().offTrackM;
        const now = Date.now();
        for (const fix of fixes) {
          const time = fix.timestamp ? Date.parse(fix.timestamp) : now;
          const projection = projectOnTrack(index, fix, lastAlongM);
          lastAlongM = projection.alongM;
          // Progress while off the trail says nothing about the pace along it.
          if (projection.offTrackM <= threshold) {
            const sample = { time, alongM: projection.alongM };
            firstSample ??= sample;
            samples.push(sample);
          }
          const verdict = monitor.onFix(projection.offTrackM, fix.accuracy, threshold, time);
          // Fixes collected after the screen was off are old news: the notification already went out.
          if (now - time < STALE_FIX_MS) handleOffTrack(verdict, projection.offTrackM);
        }
        const cutoff = now - 10 * 60_000;
        if (samples.length > 0 && samples[0].time < cutoff) samples = samples.filter((s) => s.time >= cutoff);
        const last = fixes[fixes.length - 1];
        set({ current: last, lastFixMs: last.timestamp ? Date.parse(last.timestamp) : now, error: null });
        evaluate();
      }

      /** What the person is told when they stray. On Android the service shows the notification itself. */
      function handleOffTrack(verdict: ReturnType<OffTrackMonitor["onFix"]>, offTrackM: number) {
        if (verdict === "alert" || verdict === "remind") {
          const text = t("tour.alert.text", { m: Math.round(offTrackM / 5) * 5 });
          toast.warning(t("tour.alert.title"), { description: text, id: "tour-off-track" });
          notifyLocal(t("tour.alert.title"), text);
        } else if (verdict === "back") {
          toast.dismiss("tour-off-track");
          toast.success(t("tour.backOnTrack"));
        }
      }

      /** Recomputes guidance, arrival time and warnings from the last fix and the clock. */
      function evaluate() {
        const { trail, current, lastFixMs, targetArrivalMs } = get();
        if (!trail || !index || !current || lastFixMs === null) return;
        const now = Date.now();
        const live = recentSpeedMs(samples, now);
        const speedMs = chooseSpeedMs(live, averageSpeedMs(firstSample, samples[samples.length - 1] ?? null), plannedMs);
        const guidance = computeGuidance({
          index,
          waypoints: trail.waypoints,
          position: current,
          previousAlongM: lastAlongM,
          speedMs,
          nowMs: now,
          offTrackThresholdM: useSettingsStore.getState().offTrackM,
        });
        const warnings = computeWarnings({
          guidance,
          offTrack: monitor.offTrack,
          nowMs: now,
          lastFixMs,
          targetArrivalMs,
          position: current,
          destination: trail.coordinates[trail.coordinates.length - 1],
          forecast,
        });
        set({ guidance, liveSpeedMs: live, offTrack: monitor.offTrack, warnings });
        announce(warnings, now);
        if (guidance.arrived && !arrivedAnnounced) {
          arrivedAnnounced = true;
          toast.success(t("tour.arrived"));
        }
        void refreshForecast(guidance, now);
      }

      /** Shows new warnings once (off-track is handled by the monitor). */
      function announce(warnings: TourWarning[], now: number) {
        for (const w of warnings) {
          if (w.kind === "offTrack" || w.kind === "noGps") continue;
          const last = announced.get(w.kind);
          if (last !== undefined && now - last < ANNOUNCE_COOLDOWN_MS) continue;
          announced.set(w.kind, now);
          const show = w.level === "danger" ? toast.error : toast.warning;
          show(warningText(w), { duration: 10_000 });
        }
      }

      /** The forecast around the middle of what is left of the trail, refreshed as the person moves. */
      async function refreshForecast(guidance: TourGuidance, now: number) {
        if (forecastFetching || !index || guidance.arrived) return;
        const middle = pointAtDistance(index, guidance.alongM + guidance.remainingM / 2);
        const moved = forecastFrom ? approxDistanceM(forecastFrom, middle) : Infinity;
        if (now - forecastAt < FORECAST_MAX_AGE_MS && moved < FORECAST_MOVE_M) return;
        forecastFetching = true;
        try {
          forecast = await fetchForecast(middle.latitude, middle.longitude);
          forecastFrom = middle;
          forecastAt = now;
        } catch {
          // Offline in the mountains is normal; keep the old forecast and try again soon.
          forecastAt = now - FORECAST_MAX_AGE_MS + FORECAST_RETRY_MS;
        } finally {
          forecastFetching = false;
        }
        if (get().status === "active") evaluate();
      }

      /** Collects what the native service buffered. */
      async function drainNative() {
        if (busy) return;
        busy = true;
        try {
          const { points, running, error } = await backgroundRecorder.takePoints();
          if (points.length > 0) ingest(points);
          else evaluate();
          if (error) set({ error });
          // The service is gone while the tour is on (e.g. the system stopped it): start it again.
          if (!running && get().status === "active" && !error) {
            await backgroundRecorder.start(TOUR_INTERVAL_MS, offTrackGuard());
          }
        } catch (e) {
          set({ error: message(e) });
        } finally {
          busy = false;
        }
      }

      /** Foreground-only fallback used where the native service is unavailable. */
      async function pollPosition() {
        if (busy || get().status !== "active") return;
        busy = true;
        try {
          ingest([await gpsService.getCurrentPosition()]);
        } catch (e) {
          set({ error: message(e) });
          evaluate();
        } finally {
          busy = false;
        }
      }

      async function beginCapture() {
        if (backgroundRecorder.supported) await backgroundRecorder.start(TOUR_INTERVAL_MS, offTrackGuard());
        stopTimer();
        const tick = backgroundRecorder.supported ? drainNative : pollPosition;
        void tick();
        timer = setInterval(() => void tick(), backgroundRecorder.supported ? DRAIN_INTERVAL_MS : TOUR_INTERVAL_MS);
      }

      return {
        ...INITIAL,

        start: async (trail, targetArrivalMs) => {
          if (get().status !== "idle" || starting) return;
          if (trail.coordinates.length < 2) return;
          if (!captureLock.claim("tour")) {
            set({ error: t("error.recordingActive") });
            return;
          }
          starting = true;
          set({ error: null });
          try {
            await gpsService.ensurePermission();
            void prepareLocalNotifications();
            // Drop anything left in the native buffer by an earlier, abandoned session.
            if (backgroundRecorder.supported) await backgroundRecorder.takePoints().catch(() => undefined);
            setupTrail(trail);
            guardTrack = await prepareGuardTrack(trail);
            set({ ...INITIAL, status: "active", trailId: trail.id, trail, startedAt: Date.now(), targetArrivalMs });
            await beginCapture();
          } catch (e) {
            stopTimer();
            resetWorkingState();
            captureLock.release("tour");
            set({ ...INITIAL, error: message(e) });
          } finally {
            starting = false;
          }
        },

        stop: async () => {
          stopTimer();
          captureLock.release("tour");
          resetWorkingState();
          toast.dismiss("tour-off-track");
          set({ ...INITIAL });
          if (backgroundRecorder.supported) {
            await backgroundRecorder.stop().catch(() => undefined);
            await backgroundRecorder.takePoints().catch(() => undefined);
          }
        },

        reattach: async () => {
          const { trailId } = get();
          if (!trailId) return;
          captureLock.claim("tour");
          try {
            const trail = await trailRepository.getById(trailId);
            if (!trail || trail.coordinates.length < 2) {
              await get().stop();
              return;
            }
            setupTrail(trail);
            guardTrack = await prepareGuardTrack(trail);
            set({ trail });
            await beginCapture();
          } catch (e) {
            set({ error: message(e) });
          }
        },
      };
    },
    {
      // Keeps the tour if the webview is recreated (app swiped away, process restarted).
      name: "pania.tour",
      storage: createJSONStorage(() => localStorage),
      partialize: ({ status, trailId, startedAt, targetArrivalMs }) => ({ status, trailId, startedAt, targetArrivalMs }),
      onRehydrateStorage: () => (state) => {
        if (state && state.status === "active") void state.reattach();
      },
    },
  ),
);

/** Rough distance in meters, fine for "has the person moved a few km". */
function approxDistanceM(a: { latitude: number; longitude: number }, b: { latitude: number; longitude: number }): number {
  const dy = (b.latitude - a.latitude) * 111_195;
  const dx = (b.longitude - a.longitude) * 111_195 * Math.cos((a.latitude * Math.PI) / 180);
  return Math.hypot(dx, dy);
}

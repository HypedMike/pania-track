import { useEffect, useMemo, useState } from "react";
import { currentLocale, plural, useT } from "../../../shared/i18n/i18n";
import { useNavigation } from "../../../shared/router/use_navigation";
import { ROUTES } from "../../../shared/router/routes";
import {
  computeStats,
  formatClock,
  formatDistance,
  formatElevation,
  formatPace,
} from "../../../shared/gps/trail_stats";
import TrailMap from "../components/trail_map";
import { backgroundRecorder } from "../../../shared/gps/background_recorder";
import { useRecordingStore } from "../stores/recording_store";

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex min-w-0 flex-col gap-0.5">
      <span className="text-xs text-muted">{label}</span>
      <span className="truncate font-display text-[22px] font-semibold">{value}</span>
    </div>
  );
}

function RecordingView() {
  const t = useT();
  const { goTo, goBack } = useNavigation();
  const { status, points, waypoints, startedAt, current, error, start, pause, resume, addWaypoint, elapsedMs } =
    useRecordingStore();
  const [, setTick] = useState(0);
  const [follow, setFollow] = useState(true);
  const [followKey, setFollowKey] = useState(0);

  // Begin a new recording when opened fresh; reopening keeps the one in progress.
  useEffect(() => {
    void start();
  }, [start]);

  // Re-render every second so the clock advances.
  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 1000);
    return () => clearInterval(id);
  }, []);

  const stats = useMemo(() => computeStats(points), [points]);
  const elapsed = elapsedMs();
  const paused = status === "paused";
  const startedLabel = startedAt
    ? new Date(startedAt).toLocaleTimeString(currentLocale(), { hour: "2-digit", minute: "2-digit" })
    : "…";

  async function finish() {
    await pause();
    goTo(ROUTES.saveRecording);
  }

  return (
    <main className="relative mx-auto h-dvh max-w-2xl overflow-hidden bg-map">
      <div className="absolute inset-x-0 top-0 bottom-[40%]">
        <TrailMap
          coordinates={points}
          waypoints={waypoints}
          current={current}
          fit={false}
          follow={follow}
          followKey={followKey}
          onUserMove={() => setFollow(false)}
        />
      </div>

      <div className="pointer-events-none absolute top-[calc(1.25rem+var(--safe-top))] right-4 left-4 z-[1000] flex justify-between">
        <button
          type="button"
          onClick={goBack}
          aria-label={t("recording.backLabel")}
          className="pointer-events-auto flex h-10 items-center gap-2 rounded-full bg-surface px-3.5 text-sm font-semibold shadow-md"
        >
          <span
            className={`size-2.5 rounded-full ${paused ? "bg-muted" : "animate-pulse bg-danger"}`}
            aria-hidden="true"
          />
          {status === "idle" ? t("recording.starting") : paused ? t("recording.paused") : t("recording.recording")}
        </button>
        <div className="flex h-10 items-center gap-2 rounded-full bg-surface px-3.5 text-sm font-medium shadow-md">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-brand)" strokeWidth="2.5" strokeLinecap="round" aria-hidden="true">
            <path d="M4 20v-3M10 20v-7M16 20V9M22 20V4" />
          </svg>
          {current?.accuracy !== undefined ? t("recording.gpsAccuracy", { m: Math.round(current.accuracy) }) : t("recording.gpsWaiting")}
        </div>
      </div>

      <button
        type="button"
        aria-label={t("recording.centerMap")}
        onClick={() => {
          setFollow(true);
          setFollowKey((k) => k + 1);
        }}
        className="absolute right-4 bottom-[calc(40%+16px)] z-[1000] flex size-12 items-center justify-center rounded-full bg-surface shadow-md"
      >
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
          <circle cx="12" cy="12" r="7" />
          <circle cx="12" cy="12" r="2" fill="currentColor" />
          <path d="M12 2v3M12 19v3M2 12h3M19 12h3" />
        </svg>
      </button>

      <section className="absolute inset-x-0 bottom-0 z-[1000] flex h-[40%] min-h-[330px] flex-col gap-4 rounded-t-[28px] bg-surface px-5 pt-3 pb-7 shadow-[0_-4px_24px_rgba(22,32,27,0.10)]">
        <div className="h-1 w-10 self-center rounded-full bg-line-strong" aria-hidden="true" />
        <div className="flex flex-col gap-0.5">
          <span className="text-[13px] text-muted">{t("recording.newTrail", { time: startedLabel })}</span>
          <span className="font-display text-[52px] leading-[1.05] font-semibold tracking-tight tabular-nums">
            {formatClock(elapsed)}
          </span>
        </div>

        <div className="grid grid-cols-3 gap-2">
          <Metric label={t("common.distance")} value={formatDistance(stats.distanceM)} />
          <Metric label={t("recording.avgPace")} value={formatPace(stats.distanceM, elapsed)} />
          <Metric label={t("common.elevationGain")} value={formatElevation(stats.elevationGainM, true)} />
        </div>

        <p className="rounded-xl bg-canvas px-3 py-2.5 text-[13px] text-ink-soft">
          {error
            ? error
            : t("recording.status", {
                points: t("common.pointsCount", { n: points.length }),
                waypoints: plural("common.waypoint", waypoints.length, t),
                mode: backgroundRecorder.supported ? t("recording.screenOff") : t("recording.keepOpen"),
              })}
        </p>

        <div className="mt-auto flex items-center gap-3">
          <button
            type="button"
            aria-label={t("recording.addWaypoint")}
            onClick={() => void addWaypoint()}
            disabled={status === "idle"}
            className="flex size-14 shrink-0 items-center justify-center rounded-full border border-line-strong bg-surface disabled:opacity-50"
          >
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z" />
              <path d="M12 7v5M9.5 9.5h5" />
            </svg>
          </button>
          <button
            type="button"
            onClick={() => void (paused ? resume() : pause())}
            disabled={status === "idle"}
            className="flex h-14 flex-1 items-center justify-center gap-2 rounded-full bg-ink text-base font-semibold text-on-ink disabled:opacity-50"
          >
            <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              {paused ? <path d="M7 5l12 7-12 7z" /> : (<><rect x="6" y="5" width="4" height="14" rx="1" /><rect x="14" y="5" width="4" height="14" rx="1" /></>)}
            </svg>
            {paused ? t("common.resume") : t("recording.pause")}
          </button>
          <button
            type="button"
            onClick={() => void finish()}
            disabled={status === "idle"}
            className="flex h-14 flex-1 items-center justify-center gap-2 rounded-full bg-danger text-base font-semibold text-white disabled:opacity-50"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <rect x="5" y="5" width="14" height="14" rx="2" />
            </svg>
            {t("recording.finish")}
          </button>
        </div>
      </section>
    </main>
  );
}

export default RecordingView;

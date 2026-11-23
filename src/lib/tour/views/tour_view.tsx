import { useEffect, useMemo, useState } from "react";
import { useParams } from "react-router";
import { currentLocale, useT } from "../../../shared/i18n/i18n";
import { useNavigation } from "../../../shared/router/use_navigation";
import { tourPath, trailDetailPath } from "../../../shared/router/routes";
import { formatDistance, formatDuration } from "../../../shared/gps/trail_stats";
import PageHeader from "../../../shared/ui/layout/page_header";
import TrailMap from "../../trail/components/trail_map";
import { useTrailStore } from "../../trail/stores/trail_store";
import { useSettingsStore } from "../../../shared/settings/settings_store";
import type { TourWarning } from "../tour_guidance";
import { buildTrackIndex, compassPoint, trackUpTo } from "../track_progress";
import { useTourStore } from "../tour_store";
import { formatSpeed, formatTimeOfDay, warningText } from "../warning_text";

function Metric({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="flex min-w-0 flex-col gap-0.5">
      <span className="text-xs text-muted">{label}</span>
      <span className="truncate font-display text-[22px] font-semibold">{value}</span>
      {sub && <span className="truncate text-xs text-muted">{sub}</span>}
    </div>
  );
}

function WarningRow({ warning }: { warning: TourWarning }) {
  const danger = warning.level === "danger";
  return (
    <li
      className={`flex items-start gap-2.5 rounded-xl px-3 py-2.5 text-[13px] leading-snug ${
        danger ? "bg-danger/10 text-danger" : "bg-warn-tint text-warn-ink"
      }`}
    >
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="mt-px shrink-0">
        <path d="M12 3l10 18H2L12 3z" />
        <path d="M12 10v5M12 18h.01" />
      </svg>
      <span className="font-medium">{warningText(warning)}</span>
    </li>
  );
}

/** "HH:MM" from a time input, as the next time the clock shows it. */
function nextOccurrence(hhmm: string): number | null {
  const [h, m] = hhmm.split(":").map(Number);
  if (Number.isNaN(h) || Number.isNaN(m)) return null;
  const target = new Date();
  target.setHours(h, m, 0, 0);
  if (target.getTime() <= Date.now()) target.setDate(target.getDate() + 1);
  return target.getTime();
}

function TourView() {
  const t = useT();
  const { id = "" } = useParams();
  const { goTo, goBack } = useNavigation();

  const trail = useTrailStore((s) => s.trails.find((x) => x.id === id));
  const loading = useTrailStore((s) => s.loading);
  const load = useTrailStore((s) => s.load);

  const status = useTourStore((s) => s.status);
  const activeTrailId = useTourStore((s) => s.trailId);
  const startedHere = status === "active" && activeTrailId === id;
  const otherTrail = useTrailStore((s) => s.trails.find((x) => x.id === activeTrailId));
  const offTrackThreshold = useSettingsStore((s) => s.offTrackM);
  const { current, guidance, liveSpeedMs, warnings, error, targetArrivalMs, start, stop } = useTourStore();

  const [follow, setFollow] = useState(true);
  const [followKey, setFollowKey] = useState(0);
  const [arriveBy, setArriveBy] = useState("");
  const [starting, setStarting] = useState(false);
  // Re-render every second so the arrival time and "in 12 min" stay current between fixes.
  const [, setTick] = useState(0);

  useEffect(() => {
    if (!trail) void load();
  }, [trail, load]);

  useEffect(() => {
    if (!startedHere) return;
    const timer = setInterval(() => setTick((n) => n + 1), 1000);
    return () => clearInterval(timer);
  }, [startedHere]);

  const index = useMemo(() => (trail ? buildTrackIndex(trail.coordinates) : null), [trail]);
  const completed = useMemo(
    () => (index && guidance && startedHere ? trackUpTo(index, guidance.alongM) : []),
    [index, guidance, startedHere],
  );
  const guideLine = useMemo(
    () =>
      startedHere && current && guidance?.offTrackM !== undefined && guidance.offTrackM > 15
        ? [current, guidance.nearest]
        : [],
    [startedHere, current, guidance],
  );

  if (!trail || trail.coordinates.length < 2) {
    return (
      <main className="mx-auto max-w-2xl">
        <PageHeader onBack={goBack} backLabel={t("detail.trails")} />
        <p className="px-5 pt-4 text-muted">{!trail && loading ? t("common.loading") : t("detail.notFound")}</p>
      </main>
    );
  }

  async function begin() {
    if (!trail) return;
    setStarting(true);
    await start(trail, arriveBy ? nextOccurrence(arriveBy) : null);
    setStarting(false);
  }

  async function finish() {
    if (guidance && !guidance.arrived && !window.confirm(t("tour.confirmStop"))) return;
    await stop();
    goTo(trailDetailPath(id), { replace: true });
  }

  // ── Another tour is running ──────────────────────────────────────────────────────────────
  if (status === "active" && !startedHere) {
    return (
      <main className="mx-auto flex min-h-screen max-w-2xl flex-col">
        <PageHeader onBack={goBack} backLabel={t("detail.trails")} />
        <div className="flex flex-col gap-4 px-5 pt-4">
          <p className="text-[15px]">{t("tour.otherActive", { name: otherTrail?.name ?? "…" })}</p>
          <button
            type="button"
            onClick={() => activeTrailId && goTo(tourPath(activeTrailId), { replace: true })}
            className="h-[54px] rounded-2xl bg-brand text-base font-semibold text-white active:bg-brand-dark"
          >
            {t("tour.openActive")}
          </button>
        </div>
      </main>
    );
  }

  // ── What the sheet says ──────────────────────────────────────────────────────────────────
  let instruction = t("tour.gpsWaiting");
  let detail: string | null = null;
  let arrowDeg: number | null = null;
  if (guidance) {
    arrowDeg = guidance.bearing;
    if (guidance.arrived) {
      instruction = t("tour.arrived");
    } else if (guidance.offTrackM > offTrackThreshold) {
      instruction = t("tour.offTrack");
      detail = t("tour.headTo", {
        dir: t(`tour.dir.${compassPoint(guidance.bearing)}`),
        d: formatDistance(guidance.offTrackM),
      });
    } else if (guidance.turn) {
      const { direction, sharp, inM } = guidance.turn;
      instruction = t(
        direction === "left" ? (sharp ? "tour.sharpLeft" : "tour.turnLeft") : sharp ? "tour.sharpRight" : "tour.turnRight",
        { d: formatDistance(inM) },
      );
    } else {
      instruction = t("tour.straight");
    }
    if (!detail && guidance.nextWaypoint && !guidance.arrived) {
      detail = t("tour.nextWaypoint", { name: guidance.nextWaypoint.name, d: formatDistance(guidance.nextWaypoint.inM) });
    }
  }
  const now = Date.now();
  const etaSub = guidance && !guidance.arrived ? t("tour.etaIn", { d: formatDuration(guidance.etaMs - now) }) : undefined;
  const shownAccuracy = current?.accuracy !== undefined ? `GPS ±${Math.round(current.accuracy)} m` : "GPS …";
  const target = targetArrivalMs;

  return (
    <main className="relative mx-auto h-dvh max-w-2xl overflow-hidden bg-map">
      <div className="absolute inset-x-0 top-0 bottom-[52%]">
        <TrailMap
          coordinates={trail.coordinates}
          waypoints={trail.waypoints}
          color={trail.source}
          completed={completed}
          guideLine={guideLine}
          current={startedHere ? current : null}
          fit={!(startedHere && current)}
          follow={follow}
          followKey={followKey}
          onUserMove={() => setFollow(false)}
        />
      </div>

      <div className="pointer-events-none absolute top-[calc(1.25rem+var(--safe-top))] right-4 left-4 z-[1000] flex justify-between">
        <button
          type="button"
          onClick={goBack}
          aria-label={startedHere ? t("tour.backLabel") : t("common.back")}
          className="pointer-events-auto flex h-10 items-center gap-2 rounded-full bg-surface px-3.5 text-sm font-semibold shadow-md"
        >
          {startedHere && <span className="size-2.5 animate-pulse rounded-full bg-brand" aria-hidden="true" />}
          {trail.name}
        </button>
        {startedHere && (
          <div className="flex h-10 items-center rounded-full bg-surface px-3.5 text-sm font-medium shadow-md">
            {shownAccuracy}
          </div>
        )}
      </div>

      {startedHere && (
        <button
          type="button"
          aria-label={t("tour.centerMap")}
          onClick={() => {
            setFollow(true);
            setFollowKey((k) => k + 1);
          }}
          className="absolute right-4 bottom-[calc(52%+16px)] z-[1000] flex size-12 items-center justify-center rounded-full bg-surface shadow-md"
        >
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
            <circle cx="12" cy="12" r="7" />
            <circle cx="12" cy="12" r="2" fill="currentColor" />
            <path d="M12 2v3M12 19v3M2 12h3M19 12h3" />
          </svg>
        </button>
      )}

      <section className="absolute inset-x-0 bottom-0 z-[1000] flex h-[52%] flex-col gap-3.5 overflow-y-auto rounded-t-[28px] bg-surface px-5 pt-3 pb-[calc(1.25rem+env(safe-area-inset-bottom))] shadow-[0_-4px_24px_rgba(22,32,27,0.10)]">
        <div className="h-1 w-10 shrink-0 self-center rounded-full bg-line-strong" aria-hidden="true" />

        {!startedHere ? (
          <>
            <div className="flex flex-col gap-1">
              <h1 className="font-display text-[24px] leading-tight font-bold">{t("tour.title")}</h1>
              <p className="text-sm text-ink-soft">{t("tour.setupHint")}</p>
            </div>
            <label className="flex flex-col gap-1.5">
              <span className="text-sm font-semibold">{t("tour.arriveBy")}</span>
              <div className="flex gap-2">
                <input
                  type="time"
                  value={arriveBy}
                  onChange={(e) => setArriveBy(e.target.value)}
                  className="h-12 flex-1 rounded-xl border border-line-strong bg-surface px-3.5 text-base text-ink focus:border-2 focus:border-brand-fg focus:outline-none"
                />
                {arriveBy && (
                  <button
                    type="button"
                    onClick={() => setArriveBy("")}
                    className="h-12 rounded-xl border border-line-strong bg-surface px-4 text-sm font-semibold"
                  >
                    {t("tour.arriveByClear")}
                  </button>
                )}
              </div>
              <span className="text-xs text-muted">{t("tour.arriveByHint")}</span>
            </label>
            {error && <p className="text-sm text-danger">{error}</p>}
            <button
              type="button"
              onClick={() => void begin()}
              disabled={starting}
              className="mt-auto flex h-[54px] shrink-0 items-center justify-center gap-2 rounded-2xl bg-brand text-base font-semibold text-white active:bg-brand-dark disabled:opacity-50"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                <path d="M7 5l12 7-12 7z" />
              </svg>
              {starting ? t("tour.starting") : t("tour.begin")}
            </button>
          </>
        ) : (
          <>
            <div className="flex items-center gap-4">
              <div
                className={`flex size-16 shrink-0 items-center justify-center rounded-2xl ${
                  guidance && guidance.offTrackM > offTrackThreshold ? "bg-danger/10 text-danger" : "bg-brand-tint text-brand-tint-ink"
                }`}
              >
                {arrowDeg === null ? (
                  <span className="size-3 animate-pulse rounded-full bg-current" aria-hidden="true" />
                ) : guidance?.arrived ? (
                  <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                    <path d="M5 13l4 4L19 7" />
                  </svg>
                ) : (
                  <svg
                    width="34"
                    height="34"
                    viewBox="0 0 24 24"
                    fill="currentColor"
                    aria-hidden="true"
                    style={{ transform: `rotate(${arrowDeg}deg)`, transition: "transform 0.4s" }}
                  >
                    <path d="M12 2l7 18-7-4-7 4z" />
                  </svg>
                )}
              </div>
              <div className="flex min-w-0 flex-col gap-0.5">
                <span className="font-display text-[22px] leading-tight font-semibold">{instruction}</span>
                {detail && <span className="text-[13px] text-ink-soft">{detail}</span>}
              </div>
            </div>

            <div className="grid grid-cols-3 gap-2">
              <Metric label={t("tour.remaining")} value={guidance ? formatDistance(guidance.remainingM) : "—"} />
              <Metric
                label={t("tour.eta")}
                value={guidance ? formatTimeOfDay(guidance.etaMs) : "—"}
                sub={etaSub}
              />
              <Metric label={t("tour.speed")} value={liveSpeedMs !== null ? formatSpeed(liveSpeedMs) : "—"} />
            </div>

            <div className="flex flex-col gap-1">
              <div className="h-1.5 overflow-hidden rounded-full bg-canvas" role="progressbar" aria-valuenow={Math.round(guidance?.progressPct ?? 0)} aria-valuemin={0} aria-valuemax={100}>
                <div className="h-full rounded-full bg-brand transition-[width]" style={{ width: `${guidance?.progressPct ?? 0}%` }} />
              </div>
              <span className="text-xs text-muted">
                {t("tour.progress", { pct: Math.round(guidance?.progressPct ?? 0).toLocaleString(currentLocale()) })}
                {target !== null && ` · ${t("tour.target", { time: formatTimeOfDay(target) })}`}
              </span>
            </div>

            <div className="flex flex-col gap-2">
              <h2 className="text-sm font-semibold">{t("tour.warnings")}</h2>
              {warnings.length > 0 ? (
                <ul className="flex flex-col gap-2">
                  {warnings.map((w) => (
                    <WarningRow key={w.kind} warning={w} />
                  ))}
                </ul>
              ) : (
                <p className="rounded-xl bg-canvas px-3 py-2.5 text-[13px] text-ink-soft">{t("tour.noWarnings")}</p>
              )}
              {error && <p className="text-[13px] text-danger">{error}</p>}
              <p className="text-xs text-muted">{t("tour.weatherNote")}</p>
            </div>

            <button
              type="button"
              onClick={() => void finish()}
              className="mt-auto flex h-14 shrink-0 items-center justify-center gap-2 rounded-full bg-danger text-base font-semibold text-white"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                <rect x="5" y="5" width="14" height="14" rx="2" />
              </svg>
              {guidance?.arrived ? t("tour.finish") : t("tour.stop")}
            </button>
          </>
        )}
      </section>
    </main>
  );
}

export default TourView;

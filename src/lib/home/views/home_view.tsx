import logo from "../../../assets/icon/logo.png";
import { useEffect, useMemo, useState } from "react";
import { useNavigation } from "../../../shared/router/use_navigation";
import { ROUTES, trailDetailPath } from "../../../shared/router/routes";
import {
  computeStats,
  formatDate,
  formatDistance,
  formatDuration,
  formatElevation,
} from "../../../shared/gps/trail_stats";
import TrailPreview from "../../trail/components/trail_preview";
import { useRecordingStore } from "../../trail/stores/recording_store";
import { useTrailStore } from "../../trail/stores/trail_store";
import type { TrailSource } from "../../trail/interfaces/trail";

type Filter = "all" | TrailSource;

function HomeView() {
  const { goTo } = useNavigation();
  const { trails, loading, error, load } = useTrailStore();
  const recordingStatus = useRecordingStore((state) => state.status);
  const [filter, setFilter] = useState<Filter>("all");

  useEffect(() => {
    load();
  }, [load]);

  const rows = useMemo(
    () => trails.map((trail) => ({ trail, stats: computeStats(trail.coordinates) })),
    [trails],
  );
  const totalM = rows.reduce((sum, r) => sum + r.stats.distanceM, 0);
  const visible = filter === "all" ? rows : rows.filter((r) => r.trail.source === filter);
  const count = (source: TrailSource) => trails.filter((t) => t.source === source).length;
  const tabs: { id: Filter; label: string; n: number }[] = [
    { id: "all", label: "All", n: trails.length },
    { id: "recorded", label: "Recorded", n: count("recorded") },
    { id: "imported", label: "Imported", n: count("imported") },
  ];

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col gap-5 px-5 pt-7 pb-6">
      <header className="flex items-end justify-between">
        <div className="flex flex-col gap-1">
          <div className="mb-1.5 flex items-center gap-1.5 text-brand-fg">
            <img src={logo} alt="" className="size-7 rounded-lg" />
            <span className="font-display text-xl font-bold tracking-tight">pania</span>
          </div>
          <h1 className="font-display text-[34px] leading-tight font-bold tracking-tight">Trails</h1>
          <p className="text-sm text-muted">
            {trails.length} {trails.length === 1 ? "trail" : "trails"} · {formatDistance(totalM)} in total
          </p>
        </div>
        <button
          type="button"
          aria-label="Settings"
          onClick={() => goTo(ROUTES.settings)}
          className="flex size-11 items-center justify-center rounded-full border border-line-strong bg-surface"
        >
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
            <path d="M4 7h10M18 7h2M4 17h4M12 17h8" />
            <circle cx="16" cy="7" r="2" />
            <circle cx="10" cy="17" r="2" />
          </svg>
        </button>
      </header>

      {recordingStatus !== "idle" && (
        <button
          type="button"
          onClick={() => goTo(ROUTES.record)}
          className="flex h-12 items-center justify-between rounded-2xl bg-danger px-4 text-sm font-semibold text-white"
        >
          <span className="flex items-center gap-2">
            <span className="size-2.5 animate-pulse rounded-full bg-white" aria-hidden="true" />
            {recordingStatus === "paused" ? "Recording paused" : "Recording in progress"}
          </span>
          <span>Open</span>
        </button>
      )}

      <div className="flex flex-col gap-2">
        <div className="grid grid-cols-2 gap-3">
          <button
            type="button"
            onClick={() => goTo(ROUTES.record)}
            disabled={recordingStatus !== "idle"}
            className="flex h-[60px] items-center justify-center gap-2.5 rounded-2xl bg-brand text-base font-semibold text-white active:bg-brand-dark disabled:opacity-50"
          >
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
              <circle cx="12" cy="12" r="9" />
              <circle cx="12" cy="12" r="4" fill="currentColor" stroke="none" />
            </svg>
            Record
          </button>
          <button
            type="button"
            onClick={() => goTo(ROUTES.importTrail)}
            className="flex h-[60px] items-center justify-center gap-2.5 rounded-2xl border border-line-strong bg-surface text-base font-semibold"
          >
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M12 15V4M7 9l5-5 5 5" />
              <path d="M4 15v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4" />
            </svg>
            Import GPX
          </button>
        </div>
        <p className="text-center text-[13px] text-muted">Record a new track live, or import a .gpx / .kml file</p>
      </div>

      {trails.length > 0 && (
        <div className="flex gap-2" role="tablist" aria-label="Filter trails">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              type="button"
              role="tab"
              aria-selected={filter === tab.id}
              onClick={() => setFilter(tab.id)}
              className={`h-11 rounded-full px-4 text-sm ${
                filter === tab.id ? "bg-ink font-semibold text-on-ink" : "border border-line-strong bg-surface font-medium"
              }`}
            >
              {tab.label} · {tab.n}
            </button>
          ))}
        </div>
      )}

      {loading && <p className="text-muted">Loading…</p>}
      {error && <p className="text-danger">Could not load trails: {error}</p>}
      {!loading && !error && trails.length === 0 && (
        <p className="rounded-2xl border border-line bg-surface p-5 text-center text-sm text-muted">
          No trails saved yet. Record one or import a GPX file to get started.
        </p>
      )}

      <ul className="flex flex-col gap-3">
        {visible.map(({ trail, stats }) => (
          <li key={trail.id}>
            <button
              type="button"
              onClick={() => goTo(trailDetailPath(trail.id))}
              className="flex w-full items-center gap-3.5 rounded-[18px] border border-line bg-surface p-3.5 text-left active:bg-canvas"
            >
              <TrailPreview coordinates={trail.coordinates} source={trail.source} />
              <div className="flex min-w-0 flex-1 flex-col gap-1.5">
                <span className="truncate text-base font-semibold">{trail.name}</span>
                <div className="flex items-center gap-2">
                  <span
                    className={`rounded-md px-2 py-0.5 text-xs font-semibold ${
                      trail.source === "imported" ? "bg-route-tint text-route-ink" : "bg-brand-tint text-brand-tint-ink"
                    }`}
                  >
                    {trail.source === "imported" ? "Imported GPX" : "Recorded"}
                  </span>
                  <span className="text-[13px] text-muted">{formatDate(trail.createdAt)}</span>
                </div>
                {trail.coordinates.length > 1 && (
                  <span className="text-sm text-ink-soft">
                    {formatDistance(stats.distanceM)}
                    {stats.elevationGainM !== null && ` · ${formatElevation(stats.elevationGainM, true)}`}
                    {stats.durationMs !== null && ` · ${formatDuration(stats.durationMs)}`}
                  </span>
                )}
              </div>
            </button>
          </li>
        ))}
      </ul>
    </main>
  );
}

export default HomeView;

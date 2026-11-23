import { useEffect, useMemo, useState } from "react";
import { currentLocale, plural, useT, type TFunction } from "../../../shared/i18n/i18n";
import {
  formatDistance,
  formatDuration,
  formatElevation,
} from "../../../shared/gps/trail_stats";
import { ROUTES, trailDetailPath } from "../../../shared/router/routes";
import { useNavigation } from "../../../shared/router/use_navigation";
import BottomNav from "../../../shared/ui/layout/bottom_nav";
import MainLayout from "../../../shared/ui/layout/main_layout";
import { useTrailStore } from "../../trail/stores/trail_store";
import ActivityCalendar from "../components/activity_calendar";
import DistanceChart from "../components/distance_chart";
import {
  addDays,
  buildBuckets,
  filterByPeriod,
  periodRange,
  startOfDay,
  summarize,
  toEntries,
  type Period,
  type TrailEntry,
} from "../stats_summary";

const PERIODS: { id: Period; label: Parameters<TFunction>[0] }[] = [
  { id: "week", label: "stats.week" },
  { id: "month", label: "stats.month" },
  { id: "year", label: "stats.year" },
  { id: "all", label: "stats.all" },
];

const CARD = "rounded-2xl border border-line bg-surface";

function periodSubtitle(period: Period, now: Date, t: TFunction): string {
  const locale = currentLocale();
  switch (period) {
    case "week": {
      const { start } = periodRange("week", now);
      const fmt = (d: Date) => d.toLocaleDateString(locale, { month: "short", day: "numeric" });
      return `${fmt(start!)} – ${fmt(addDays(start!, 6))}`;
    }
    case "month":
      return now.toLocaleDateString(locale, { month: "long", year: "numeric" });
    case "year":
      return String(now.getFullYear());
    case "all":
      return t("stats.subtitleAll");
  }
}

function BigTile({ label, value }: { label: string; value: string }) {
  return (
    <div className={`${CARD} flex flex-col gap-1 p-3.5`}>
      <span className="text-[13px] text-muted">{label}</span>
      <span className="font-display text-[28px] font-semibold">{value}</span>
    </div>
  );
}

function SmallStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col gap-0.5">
      <span className="text-xs text-muted">{label}</span>
      <span className="font-display text-[19px] font-semibold">{value}</span>
    </div>
  );
}

function Section({ title, aside, children }: { title: string; aside?: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-2.5">
      <div className="flex items-baseline justify-between">
        <h2 className="text-base font-semibold">{title}</h2>
        {aside && <span className="text-[13px] text-muted">{aside}</span>}
      </div>
      {children}
    </section>
  );
}

function StatsView() {
  const t = useT();
  const { goTo } = useNavigation();
  const { trails, load } = useTrailStore();
  const [period, setPeriod] = useState<Period>("month");

  useEffect(() => {
    load();
  }, [load]);

  const now = useMemo(() => new Date(), []);
  const entries = useMemo(() => toEntries(trails), [trails]);
  const inPeriod = useMemo(() => filterByPeriod(entries, period, now), [entries, period, now]);
  const summary = useMemo(() => summarize(inPeriod), [inPeriod]);
  const buckets = useMemo(() => buildBuckets(period, inPeriod, now), [period, inPeriod, now]);

  const { start, end } = periodRange(period, now);
  const today = startOfDay(now);
  const showCalendar = period === "week" || period === "month";
  const elapsedDays =
    start && showCalendar ? Math.round((today.getTime() - start.getTime()) / 86_400_000) + 1 : 0;

  const { records } = summary;
  const recordRows: { label: string; entry: TrailEntry | undefined; value: string }[] = [
    { label: t("stats.recLongest"), entry: records.longest, value: formatDistance(records.longest?.stats.distanceM ?? 0) },
    { label: t("stats.recClimb"), entry: records.climb, value: formatElevation(records.climb?.stats.elevationGainM ?? null, true) },
    { label: t("stats.recHighest"), entry: records.highest, value: formatElevation(records.highest?.stats.highestM ?? null) },
    { label: t("stats.recTime"), entry: records.time, value: formatDuration(records.time?.stats.durationMs ?? null) },
  ];
  const visibleRecords = recordRows.filter((r) => r.entry);

  const splitTotal = summary.recorded.distanceM + summary.imported.distanceM;
  const recordedPct = splitTotal > 0 ? Math.round((summary.recorded.distanceM / splitTotal) * 100) : 0;

  return (
    <div className="flex min-h-screen flex-col">
      <MainLayout
        header={
          <header className="flex flex-col gap-1">
            <h1 className="font-display text-[34px] leading-tight font-bold tracking-tight">{t("stats.title")}</h1>
            <p className="text-sm text-muted">{periodSubtitle(period, now, t)}</p>
          </header>
        }
        className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-5 px-5 pt-[calc(1.75rem+var(--safe-top))] pb-6"
      >
        <div
          role="tablist"
          aria-label={t("stats.period")}
          className="grid grid-cols-4 gap-1 rounded-[14px] border border-line bg-surface p-1"
        >
          {PERIODS.map((p) => {
            const selected = p.id === period;
            return (
              <button
                key={p.id}
                type="button"
                role="tab"
                aria-selected={selected}
                onClick={() => setPeriod(p.id)}
                className={`h-11 rounded-[10px] text-sm ${
                  selected ? "bg-ink font-semibold text-on-ink" : "font-medium text-ink-soft"
                }`}
              >
                {t(p.label)}
              </button>
            );
          })}
        </div>

        <div className="grid grid-cols-2 gap-2.5">
          <BigTile label={t("common.distance")} value={formatDistance(summary.distanceM)} />
          <BigTile label={t("common.elevationGain")} value={formatElevation(summary.count > 0 ? summary.gainM : null, true)} />
          <BigTile label={t("stats.movingTime")} value={formatDuration(summary.movingMs > 0 ? summary.movingMs : null)} />
          <BigTile label={t("stats.trails")} value={String(summary.count)} />
        </div>

        {summary.count === 0 ? (
          <p className={`${CARD} p-5 text-center text-sm text-muted`}>{t("stats.empty")}</p>
        ) : (
          <>
            <DistanceChart period={period} buckets={buckets} />

            <Section title={t("stats.averages")}>
              <div className={`${CARD} grid grid-cols-3 gap-2 p-3.5`}>
                <SmallStat label={t("common.distance")} value={formatDistance(summary.avgDistanceM)} />
                <SmallStat label={t("detail.gain")} value={formatElevation(summary.avgGainM, true)} />
                <SmallStat
                  label={t("stats.speed")}
                  value={summary.avgSpeedKmh === null ? "—" : `${summary.avgSpeedKmh.toFixed(1)} km/h`}
                />
              </div>
            </Section>

            {visibleRecords.length > 0 && (
              <Section title={t("stats.records")}>
                <ul className={`${CARD} flex flex-col`}>
                  {visibleRecords.map((r) => (
                    <li key={r.label} className="border-line not-first:border-t">
                      <button
                        type="button"
                        onClick={() => goTo(trailDetailPath(r.entry!.trail.id))}
                        className="flex min-h-11 w-full items-center justify-between gap-3 px-4 py-3.5 text-left"
                      >
                        <span className="flex min-w-0 flex-col gap-0.5">
                          <span className="text-[13px] text-muted">{r.label}</span>
                          <span className="truncate text-[15px] font-semibold">{r.entry!.trail.name}</span>
                        </span>
                        <span className="font-display text-xl font-semibold whitespace-nowrap">{r.value}</span>
                      </button>
                    </li>
                  ))}
                </ul>
              </Section>
            )}

            <Section title={t("stats.split")}>
              <div className={`${CARD} flex flex-col gap-3 p-4`}>
                <div
                  role="img"
                  aria-label={t("stats.splitAlt", { recorded: recordedPct, imported: 100 - recordedPct })}
                  className="flex h-3.5 gap-[3px] overflow-hidden rounded-[7px]"
                >
                  {summary.recorded.distanceM > 0 && (
                    <div className="bg-brand" style={{ flex: summary.recorded.distanceM }} />
                  )}
                  {summary.imported.distanceM > 0 && (
                    <div className="bg-route" style={{ flex: summary.imported.distanceM }} />
                  )}
                </div>
                <div className="grid grid-cols-2 gap-2">
                  <SmallStat
                    label={t("stats.recordedCount", { trails: plural("common.trail", summary.recorded.count, t) })}
                    value={formatDistance(summary.recorded.distanceM)}
                  />
                  <SmallStat
                    label={t("stats.importedCount", { trails: plural("common.trail", summary.imported.count, t) })}
                    value={formatDistance(summary.imported.distanceM)}
                  />
                </div>
              </div>
            </Section>

            {showCalendar && start && end && (
              <Section
                title={t("stats.activeDays")}
                aside={t("stats.activeOf", { n: summary.activeDays.size, total: elapsedDays })}
              >
                <ActivityCalendar start={start} end={end} now={now} activeDays={summary.activeDays} />
              </Section>
            )}
          </>
        )}

        <button
          type="button"
          onClick={() => goTo(ROUTES.insights)}
          className={`${CARD} flex min-h-14 items-center justify-between gap-3 p-4 text-left`}
        >
          <span className="flex flex-col">
            <span className="text-sm font-semibold">{t("insights.open")}</span>
            <span className="text-sm text-muted">{t("insights.openHint")}</span>
          </span>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="shrink-0 text-muted">
            <path d="M9 6l6 6-6 6" />
          </svg>
        </button>
      </MainLayout>
      <BottomNav current="stats" />
    </div>
  );
}

export default StatsView;

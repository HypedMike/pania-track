import { currentLocale, useT } from "../../../shared/i18n/i18n";
import type { Bucket, Period } from "../stats_summary";

const BAR_AREA_PX = 110;
const MIN_BAR_PX = 4;
/** Above this many bars the per-bar value labels no longer fit. */
const MAX_LABELLED_BARS = 7;

function barLabel(period: Period, start: Date): string {
  const locale = currentLocale();
  switch (period) {
    case "week":
      return start.toLocaleDateString(locale, { weekday: "short" });
    case "month":
      return start.toLocaleDateString(locale, { month: "short", day: "numeric" });
    case "year":
      return start.toLocaleDateString(locale, { month: "narrow" });
    case "all":
      return String(start.getFullYear());
  }
}

const km = (m: number) => (m / 1000).toFixed(1);

function DistanceChart({ period, buckets }: { period: Period; buckets: Bucket[] }) {
  const t = useT();
  const max = Math.max(...buckets.map((b) => b.recordedM + b.importedM), 0);
  const showValues = buckets.length <= MAX_LABELLED_BARS;
  const title = t(`stats.chart.${period}`);
  const alt = buckets
    .map((b) => `${barLabel(period, b.start)}: ${km(b.recordedM + b.importedM)} km`)
    .join(", ");

  return (
    <section className="flex flex-col gap-3.5 rounded-2xl border border-line bg-surface p-4">
      <div className="flex items-baseline justify-between">
        <h2 className="text-base font-semibold">{title}</h2>
        <span className="text-xs text-muted">km</span>
      </div>
      <div
        role="img"
        aria-label={`${title}. ${alt}`}
        className="grid h-[170px] items-end gap-2.5"
        style={{ gridTemplateColumns: `repeat(${buckets.length}, minmax(0, 1fr))` }}
      >
        {buckets.map((b) => {
          const total = b.recordedM + b.importedM;
          const barPx = total > 0 ? Math.max(MIN_BAR_PX, Math.round((total / max) * BAR_AREA_PX)) : MIN_BAR_PX;
          return (
            <div key={b.start.getTime()} className="flex flex-col items-center gap-1.5">
              {showValues && <span className="text-xs font-semibold text-ink-soft">{total > 0 ? km(total) : "0"}</span>}
              <div
                className="flex w-full flex-col-reverse overflow-hidden rounded-t-lg rounded-b-sm"
                style={{ height: barPx }}
              >
                {total === 0 && <div className="size-full bg-line-strong" />}
                {b.recordedM > 0 && <div className="bg-brand" style={{ flex: b.recordedM }} />}
                {b.importedM > 0 && <div className="bg-route" style={{ flex: b.importedM }} />}
              </div>
              <span className="text-xs text-muted">{barLabel(period, b.start)}</span>
            </div>
          );
        })}
      </div>
      <div className="flex gap-4 text-xs text-ink-soft">
        <span className="flex items-center gap-1.5">
          <span className="size-2.5 rounded-[3px] bg-brand" />
          {t("trail.sourceRecorded")}
        </span>
        <span className="flex items-center gap-1.5">
          <span className="size-2.5 rounded-[3px] bg-route" />
          {t("trail.sourceImported")}
        </span>
      </div>
    </section>
  );
}

export default DistanceChart;

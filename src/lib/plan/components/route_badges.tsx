import { useT } from "../../../shared/i18n/i18n";
import { formatDistance, formatDuration, formatElevation } from "../../../shared/gps/trail_stats";
import type { Difficulty, RouteAnalysis } from "../route_analysis";

const CHIP = "rounded-md px-2 py-0.5 text-xs whitespace-nowrap";

export function DifficultyChip({ difficulty }: { difficulty: Difficulty }) {
  const t = useT();
  const expert = difficulty === "EE" || difficulty === "EEA";
  return (
    <span
      className={`${CHIP} font-semibold ${expert ? "bg-warn-tint text-warn-ink" : "bg-brand-tint text-brand-tint-ink"}`}
    >
      {t(`difficulty.${difficulty}`)}
    </span>
  );
}

export function InfoChip({ children }: { children: React.ReactNode }) {
  return <span className={`${CHIP} bg-line font-medium text-ink-soft`}>{children}</span>;
}

/** Gain and estimated time, the part of the summary after the distance: "+702 m · ~4h 10m". */
export function climbAndTime(a: RouteAnalysis): string {
  return `${formatElevation(a.gainM, true)} · ~${formatDuration(a.estimatedMs)}`;
}

/** "11.8 km · +702 m · ~4h 10m" */
export function routeLine(a: RouteAnalysis): string {
  return `${formatDistance(a.distanceM)} · ${climbAndTime(a)}`;
}

import {
  formatDate,
  formatDistance,
  formatDuration,
  formatElevation,
  type TrailStats,
} from "../../../shared/gps/trail_stats";
import TrailPreview from "../../trail/components/trail_preview";
import type { Trail } from "../../trail/interfaces/trail";

interface TrailListItemProps {
  trail: Trail;
  stats: TrailStats;
  onSelect: () => void;
}

function TrailListItem({ trail, stats, onSelect }: TrailListItemProps) {
  return (
    <li>
      <button
        type="button"
        onClick={onSelect}
        className="flex w-full items-center gap-3.5 rounded-[18px] border border-line bg-surface p-3.5 text-left active:bg-canvas"
      >
        <TrailPreview coordinates={trail.coordinates} source={trail.source} />
        <div className="flex min-w-0 flex-1 flex-col gap-1.5">
          <span className="truncate text-base font-semibold">{trail.name}</span>
          <div className="flex items-center gap-2">
            <span
              className={`rounded-md px-2 py-0.5 text-xs font-semibold ${
                trail.source === "imported"
                  ? "bg-route-tint text-route-ink"
                  : "bg-brand-tint text-brand-tint-ink"
              }`}
            >
              {trail.source === "imported" ? "Imported GPX" : "Recorded"}
            </span>
            <span className="text-[13px] text-muted">
              {formatDate(trail.createdAt)}
            </span>
          </div>
          {trail.coordinates.length > 1 && (
            <span className="text-sm text-ink-soft">
              {formatDistance(stats.distanceM)}
              {stats.elevationGainM !== null &&
                ` · ${formatElevation(stats.elevationGainM, true)}`}
              {stats.durationMs !== null &&
                ` · ${formatDuration(stats.durationMs)}`}
            </span>
          )}
        </div>
      </button>
    </li>
  );
}

export default TrailListItem;

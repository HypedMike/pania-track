import { useMemo, useState, type PointerEvent } from "react";
import { formatDistance, formatElevation } from "../../../shared/gps/trail_stats";
import { useT } from "../../../shared/i18n/i18n";
import type { GpsCoordinate } from "../../trail/interfaces/gps_coordinate";
import {
  altAt,
  binAt,
  buildProfile,
  checkpointDistances,
  GRADE_STEPS,
  gradeClass,
  pointAt,
  type ProfilePoint,
} from "../route_profile";
import { checkpointLabel } from "./plan_map";

const W = 340;
const H = 80;
const PAD_TOP = 6;
const GRADE_FILL = ["var(--color-grade-0)", "var(--color-grade-1)", "var(--color-grade-2)", "var(--color-grade-3)"];

interface SteepnessProfileProps {
  coordinates: GpsCoordinate[];
  /** Marked on the distance axis, with the same labels as the map pins. */
  checkpoints?: GpsCoordinate[];
  /** Called with the point under the finger/pointer, or null when it leaves. */
  onCursor?: (p: GpsCoordinate | null) => void;
}

/** Elevation against distance, with each stretch filled by how steep it is. Scrub to read a point. */
function SteepnessProfile({ coordinates, checkpoints = [], onCursor }: SteepnessProfileProps) {
  const t = useT();
  const profile = useMemo(() => buildProfile(coordinates), [coordinates]);
  const marks = useMemo(
    () => (profile ? checkpointDistances(profile, checkpoints) : []),
    [profile, checkpoints],
  );
  const [cursor, setCursor] = useState<ProfilePoint | null>(null);

  const shapes = useMemo(() => {
    if (!profile) return null;
    const { points, bins, totalM, minAlt, maxAlt } = profile;
    const range = maxAlt - minAlt || 1;
    const x = (d: number) => (d / totalM) * W;
    const y = (alt: number) => PAD_TOP + (1 - (alt - minAlt) / range) * (H - PAD_TOP);
    const line = points.map((p) => `${x(p.d).toFixed(1)},${y(p.alt).toFixed(1)}`).join(" ");
    const areas = bins.map((b) => {
      const inside = points.filter((p) => p.d > b.from && p.d < b.to);
      const edge = (d: number) => `${x(d).toFixed(1)},${y(altAt(points, d)).toFixed(1)}`;
      const top = [edge(b.from), ...inside.map((p) => `${x(p.d).toFixed(1)},${y(p.alt).toFixed(1)}`), edge(b.to)];
      return { fill: GRADE_FILL[gradeClass(b.gradePct)], points: `${x(b.from)},${H} ${top.join(" ")} ${x(b.to)},${H}` };
    });
    return { line, areas, x, y };
  }, [profile]);

  if (!profile || !shapes) return null;
  const steepest = Math.max(...profile.bins.map((b) => Math.abs(b.gradePct)));

  function move(e: PointerEvent<HTMLDivElement>) {
    if (!profile) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const frac = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
    const p = pointAt(profile, frac * profile.totalM);
    setCursor(p);
    onCursor?.(p.coordinate);
  }
  function leave() {
    setCursor(null);
    onCursor?.(null);
  }

  const grade = cursor ? Math.round(binAt(profile, cursor.d).gradePct) : null;

  return (
    <section className="flex shrink-0 flex-col gap-1.5">
      <div className="flex items-baseline justify-between gap-2 text-xs text-muted" aria-live="polite">
        <h2 className="text-[13px] font-semibold text-ink">{t("profile.title")}</h2>
        {cursor && grade !== null ? (
          <span className="font-medium text-ink-soft">
            {t("profile.readout", {
              d: formatDistance(cursor.d),
              alt: formatElevation(cursor.alt),
              grade: `${grade > 0 ? "+" : ""}${grade}`,
            })}
          </span>
        ) : (
          <span>
            {formatElevation(profile.minAlt)} – {formatElevation(profile.maxAlt)}
          </span>
        )}
      </div>

      <div
        className="relative cursor-crosshair touch-pan-y select-none"
        onPointerMove={move}
        onPointerDown={move}
        onPointerLeave={leave}
        onPointerCancel={leave}
      >
        <svg
          viewBox={`0 0 ${W} ${H}`}
          preserveAspectRatio="none"
          role="img"
          aria-label={t("profile.alt", {
            min: Math.round(profile.minAlt),
            max: Math.round(profile.maxAlt),
            steepest: Math.round(steepest),
          })}
          className="block h-20 w-full rounded-lg bg-canvas"
        >
          {shapes.areas.map((a, i) => (
            <polygon key={i} points={a.points} fill={a.fill} />
          ))}
          <polyline
            points={shapes.line}
            fill="none"
            stroke="var(--color-ink)"
            strokeWidth="1.5"
            strokeLinejoin="round"
            vectorEffect="non-scaling-stroke"
          />
          {marks.map((d, i) => (
            <line key={i} x1={shapes.x(d)} x2={shapes.x(d)} y1={0} y2={H} stroke="var(--color-ink)" strokeWidth="1" strokeDasharray="2 3" vectorEffect="non-scaling-stroke" />
          ))}
          {cursor && (
            <line x1={shapes.x(cursor.d)} x2={shapes.x(cursor.d)} y1={0} y2={H} stroke="var(--color-ink)" strokeWidth="2" vectorEffect="non-scaling-stroke" />
          )}
        </svg>
        {/* Labels in HTML so they don't stretch with the chart. */}
        {marks.map((d, i) => (
          <span
            key={i}
            aria-hidden="true"
            className="absolute top-0.5 flex size-4 -translate-x-1/2 items-center justify-center rounded-full border border-ink bg-surface text-[9px] font-bold"
            style={{ left: `${Math.min(97, Math.max(3, (d / profile.totalM) * 100))}%` }}
          >
            {checkpointLabel(i)}
          </span>
        ))}
      </div>

      <div className="flex items-center justify-between gap-2 text-[11px] text-muted">
        <span>0</span>
        <ul className="flex flex-wrap gap-x-2.5 gap-y-0.5" aria-label={t("profile.legend")}>
          {GRADE_FILL.map((fill, i) => (
            <li key={i} className="flex items-center gap-1">
              <span className="size-2.5 rounded-sm" style={{ background: fill }} aria-hidden="true" />
              {i === 0
                ? `< ${GRADE_STEPS[0]}%`
                : i < GRADE_STEPS.length
                  ? `${GRADE_STEPS[i - 1]}–${GRADE_STEPS[i]}%`
                  : `> ${GRADE_STEPS[GRADE_STEPS.length - 1]}%`}
            </li>
          ))}
        </ul>
        <span>{formatDistance(profile.totalM)}</span>
      </div>
    </section>
  );
}

/** Placeholder with the profile's exact layout, shown while the route is being computed. */
export function SteepnessProfileSkeleton() {
  const t = useT();
  const pulse = "bg-line motion-safe:animate-pulse";
  const bar = `rounded ${pulse}`;
  return (
    <section className="flex shrink-0 flex-col gap-1.5" aria-busy="true" aria-label={t("profile.loading")}>
      <div className="flex items-baseline justify-between gap-2">
        <h2 className="text-[13px] font-semibold text-ink">{t("profile.title")}</h2>
        <span className={`h-3 w-20 ${bar}`} aria-hidden="true" />
      </div>
      <div className={`h-20 w-full rounded-lg ${pulse}`} aria-hidden="true" />
      <div className="flex items-center justify-between gap-2" aria-hidden="true">
        <span className={`h-2.5 w-3 ${bar}`} />
        <span className={`h-2.5 w-48 ${bar}`} />
        <span className={`h-2.5 w-10 ${bar}`} />
      </div>
    </section>
  );
}

export default SteepnessProfile;

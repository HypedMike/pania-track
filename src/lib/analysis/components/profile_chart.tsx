import type { Segment, Stop } from "../../../shared/analysis/analysis_api";

const W = 320;
const H = 110;
const PAD = 8;
const MAX_POINTS = 400;

interface ProfileChartProps {
  /** Meters from the start, one per point. */
  distances: number[];
  /** Altitude of each point (meters), `undefined` where unknown. */
  altitudes: (number | undefined)[];
  segments?: Segment[];
  stops?: Stop[];
  /** Index of the point the replay is at. */
  cursor?: number;
  ariaLabel: string;
}

const SEGMENT_FILL: Record<Segment["kind"], string> = {
  climb: "var(--color-grade-2)",
  descent: "var(--color-route)",
  flat: "transparent",
};

/** Altitude against distance, with climbs and descents shaded, stops marked and a replay cursor. */
function ProfileChart({ distances, altitudes, segments = [], stops = [], cursor, ariaLabel }: ProfileChartProps) {
  const known: { d: number; a: number }[] = [];
  for (let i = 0; i < distances.length; i++) {
    const a = altitudes[i];
    if (a !== undefined) known.push({ d: distances[i], a });
  }
  if (known.length < 2) return null;
  const total = distances[distances.length - 1] || 1;
  const min = Math.min(...known.map((k) => k.a));
  const max = Math.max(...known.map((k) => k.a));
  const range = max - min || 1;
  const x = (d: number) => (d / total) * W;
  const y = (a: number) => H - PAD - ((a - min) / range) * (H - 2 * PAD);
  const step = Math.max(1, Math.ceil(known.length / MAX_POINTS));
  const thinned = known.filter((_, i) => i % step === 0 || i === known.length - 1);
  const line = thinned.map((k) => `${x(k.d).toFixed(1)},${y(k.a).toFixed(1)}`).join(" ");

  const altitudeAt = (d: number): number => {
    let lo = 0;
    while (lo + 1 < known.length && known[lo + 1].d < d) lo++;
    return known[lo].a;
  };
  const cursorD = cursor !== undefined ? distances[Math.min(cursor, distances.length - 1)] : undefined;

  return (
    <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={ariaLabel} className="block w-full">
      {segments.map((s, i) => (
        <rect
          key={i}
          x={x(s.startM)}
          y="0"
          width={Math.max(1, x(s.endM) - x(s.startM))}
          height={H}
          fill={SEGMENT_FILL[s.kind]}
          fillOpacity="0.16"
        />
      ))}
      <polygon points={`0,${H} ${line} ${W},${H}`} fill="var(--color-route)" fillOpacity="0.1" />
      <polyline points={line} fill="none" stroke="var(--color-route)" strokeWidth="2.2" strokeLinejoin="round" />
      {stops.map((s, i) => (
        <circle key={i} cx={x(s.alongM)} cy={y(altitudeAt(s.alongM))} r="4" fill="var(--color-alt)" stroke="var(--color-surface)" strokeWidth="1.5" />
      ))}
      {cursorD !== undefined && (
        <>
          <line x1={x(cursorD)} x2={x(cursorD)} y1="0" y2={H} stroke="var(--color-ink)" strokeWidth="1.5" strokeDasharray="3 3" />
          <circle cx={x(cursorD)} cy={y(altitudeAt(cursorD))} r="5" fill="var(--color-brand)" stroke="var(--color-surface)" strokeWidth="2" />
        </>
      )}
    </svg>
  );
}

export default ProfileChart;

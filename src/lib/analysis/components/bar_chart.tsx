/**
 * Plain vertical bars, one per value, with a label under some of them. Values may be negative
 * (bars then hang from a zero line). `tone` picks the colour of each bar.
 */
export type Tone = "brand" | "route" | "muted" | "good" | "bad";

const FILL: Record<Tone, string> = {
  brand: "var(--color-brand)",
  route: "var(--color-route)",
  muted: "var(--color-line-strong)",
  good: "var(--color-brand)",
  bad: "var(--color-danger)",
};

interface BarChartProps {
  values: number[];
  labels?: string[];
  /** Label every n-th bar. */
  labelEvery?: number;
  tones?: Tone[];
  /** Index of a bar to draw in full colour while the others are dimmed. */
  highlight?: number | null;
  height?: number;
  ariaLabel: string;
}

const W = 320;

function BarChart({ values, labels, labelEvery = 1, tones, highlight = null, height = 96, ariaLabel }: BarChartProps) {
  if (values.length === 0) return null;
  const labelH = labels ? 14 : 0;
  const plotH = height - labelH;
  const max = Math.max(0, ...values);
  const min = Math.min(0, ...values);
  const range = max - min || 1;
  const zeroY = 4 + ((max - 0) / range) * (plotH - 8);
  const slot = W / values.length;
  const barW = Math.max(2, slot * 0.7);

  return (
    <svg viewBox={`0 0 ${W} ${height}`} role="img" aria-label={ariaLabel} className="block w-full">
      <line x1="0" x2={W} y1={zeroY} y2={zeroY} stroke="var(--color-line)" strokeWidth="1" />
      {values.map((v, i) => {
        const h = (Math.abs(v) / range) * (plotH - 8);
        const y = v >= 0 ? zeroY - h : zeroY;
        const dimmed = highlight !== null && highlight !== i;
        return (
          <rect
            key={i}
            x={i * slot + (slot - barW) / 2}
            y={y}
            width={barW}
            height={Math.max(h, v === 0 ? 0 : 1)}
            rx="2"
            fill={FILL[tones?.[i] ?? "brand"]}
            fillOpacity={dimmed ? 0.35 : 1}
          />
        );
      })}
      {labels?.map(
        (label, i) =>
          i % labelEvery === 0 && (
            <text key={i} x={i * slot + slot / 2} y={height - 3} textAnchor="middle" fontSize="9" fill="var(--color-muted)">
              {label}
            </text>
          ),
      )}
    </svg>
  );
}

export default BarChart;

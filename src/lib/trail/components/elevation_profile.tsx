import type { GpsCoordinate } from "../interfaces/gps_coordinate";

const W = 320;
const H = 96;

function ElevationProfile({ coordinates }: { coordinates: GpsCoordinate[] }) {
  const alts = coordinates.map((c) => c.altitude).filter((a): a is number => a !== undefined);
  if (alts.length < 2) return null;

  const min = Math.min(...alts);
  const max = Math.max(...alts);
  const range = max - min || 1;
  const line = alts
    .map((a, i) => `${((i / (alts.length - 1)) * W).toFixed(1)},${(H - 8 - ((a - min) / range) * (H - 16)).toFixed(1)}`)
    .join(" ");

  return (
    <section className="flex flex-col gap-2 rounded-2xl border border-line bg-surface p-4">
      <div className="flex items-baseline justify-between">
        <h2 className="text-sm font-semibold">Elevation</h2>
        <span className="text-xs text-muted">
          {Math.round(min)} – {Math.round(max)} m
        </span>
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={`Elevation profile from ${Math.round(min)} to ${Math.round(max)} metres`} className="block w-full">
        <polygon points={`0,${H} ${line} ${W},${H}`} fill="var(--color-route)" fillOpacity="0.14" />
        <polyline points={line} fill="none" stroke="var(--color-route)" strokeWidth="2.5" strokeLinejoin="round" />
      </svg>
    </section>
  );
}

export default ElevationProfile;

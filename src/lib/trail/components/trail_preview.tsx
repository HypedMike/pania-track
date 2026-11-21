import type { GpsCoordinate } from "../interfaces/gps_coordinate";
import type { TrailSource } from "../interfaces/trail";

const SIZE = 72;
const PAD = 10;

/** Small schematic of a trail's shape, used as a list thumbnail. */
function TrailPreview({ coordinates, source }: { coordinates: GpsCoordinate[]; source: TrailSource }) {
  if (coordinates.length < 2) {
    return <div className="size-[72px] shrink-0 rounded-xl bg-map" aria-hidden="true" />;
  }

  const lats = coordinates.map((c) => c.latitude);
  const lons = coordinates.map((c) => c.longitude);
  const minLat = Math.min(...lats);
  const minLon = Math.min(...lons);
  // Longitude degrees shrink with latitude; correct so the shape isn't stretched.
  const lonScale = Math.cos((((minLat + Math.max(...lats)) / 2) * Math.PI) / 180);
  const w = (Math.max(...lons) - minLon) * lonScale || 1e-9;
  const h = Math.max(...lats) - minLat || 1e-9;
  const scale = (SIZE - PAD * 2) / Math.max(w, h);
  const offX = (SIZE - w * scale) / 2;
  const offY = (SIZE - h * scale) / 2;

  const points = coordinates.map((c) => [
    offX + (c.longitude - minLon) * lonScale * scale,
    SIZE - (offY + (c.latitude - minLat) * scale),
  ]);
  const start = points[0];

  return (
    <svg
      width={SIZE}
      height={SIZE}
      viewBox={`0 0 ${SIZE} ${SIZE}`}
      role="img"
      aria-label="Route preview"
      className="shrink-0 rounded-xl bg-map"
    >
      <polyline
        points={points.map((p) => p.join(",")).join(" ")}
        fill="none"
        stroke={source === "imported" ? "var(--color-route)" : "var(--color-brand-fg)"}
        strokeWidth="3.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <circle cx={start[0]} cy={start[1]} r="4" fill="var(--color-surface)" stroke="var(--color-ink)" strokeWidth="2" />
    </svg>
  );
}

export default TrailPreview;

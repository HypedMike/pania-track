import { useEffect, useMemo } from "react";
import { MapContainer, Rectangle, TileLayer, useMap } from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import type { Heatmap } from "../../../shared/analysis/analysis_api";

/** Drawing more than this many cells makes the map sluggish. The most visited are kept. */
const MAX_DRAWN = 4_000;
/** Light to dark: once, a few times, often. */
const RAMP = ["#f2cf5b", "#e07b39", "#c2410c", "#9f2f1c"];

function color(count: number, max: number): string {
  if (max <= 1) return RAMP[1];
  const t = (count - 1) / (max - 1);
  return RAMP[Math.min(RAMP.length - 1, Math.floor(t * RAMP.length))];
}

function Fit({ bounds }: { bounds: [number, number, number, number] }) {
  const map = useMap();
  useEffect(() => {
    map.fitBounds(L.latLngBounds([bounds[0], bounds[1]], [bounds[2], bounds[3]]), { padding: [24, 24] });
  }, [map, bounds]);
  return null;
}

/** Where the person has been, darker where they went more often; blank map is unexplored ground. */
function HeatmapMap({ heatmap }: { heatmap: Heatmap }) {
  const cells = useMemo(() => heatmap.cells.slice(0, MAX_DRAWN), [heatmap]);
  const bounds = heatmap.bounds;
  return (
    <MapContainer
      center={bounds ? [(bounds[0] + bounds[2]) / 2, (bounds[1] + bounds[3]) / 2] : [41.9, 12.5]}
      zoom={bounds ? 10 : 5}
      zoomControl={false}
      preferCanvas
      style={{ height: "100%", width: "100%", minHeight: 260 }}
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      {cells.map((c, i) => (
        <Rectangle
          key={i}
          bounds={[
            [c.latitude - heatmap.latStep / 2, c.longitude - heatmap.lonStep / 2],
            [c.latitude + heatmap.latStep / 2, c.longitude + heatmap.lonStep / 2],
          ]}
          pathOptions={{ stroke: false, fillColor: color(c.count, heatmap.maxCount), fillOpacity: 0.6 }}
        />
      ))}
      {bounds && <Fit bounds={bounds} />}
    </MapContainer>
  );
}

export default HeatmapMap;

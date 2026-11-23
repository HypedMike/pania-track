import { useEffect, useMemo } from "react";
import { CircleMarker, MapContainer, Polyline, TileLayer, Tooltip, useMap, useMapEvents } from "react-leaflet";
import L, { type LatLngTuple } from "leaflet";
import "leaflet/dist/leaflet.css";
import { useColorScheme } from "../../../shared/theme/use_color_scheme";
import { PALETTE } from "../../trail/components/trail_map";
import type { Difficulty, SharedTrail } from "../sharing_api";

const DEFAULT_CENTER: LatLngTuple = [41.9028, 12.4964];

const DIFFICULTY_COLOR: Record<"light" | "dark", Record<Difficulty, string>> = {
  light: { easy: "#127A4B", moderate: "#B45309", hard: "#9F2F1C" },
  dark: { easy: "#4CC38A", moderate: "#F59E0B", hard: "#F0836E" },
};

function FitResults({ points }: { points: LatLngTuple[] }) {
  const map = useMap();
  useEffect(() => {
    if (points.length > 0) map.fitBounds(L.latLngBounds(points), { padding: [36, 36], maxZoom: 14 });
  }, [map, points]);
  return null;
}

function CenterTracker({ onCenter }: { onCenter: (lat: number, lon: number) => void }) {
  const map = useMap();
  useMapEvents({
    moveend: () => {
      const c = map.getCenter();
      onCenter(c.lat, c.lng);
    },
  });
  return null;
}

/** Map of shared trails: one marker per trail start, the selected trail's path drawn in full. */
function ExploreMap({
  results,
  selectedId,
  me,
  onSelect,
  onCenter,
}: {
  results: SharedTrail[];
  selectedId: string | null;
  /** The user's own position, when known. */
  me: LatLngTuple | null;
  onSelect: (eventId: string) => void;
  onCenter: (lat: number, lon: number) => void;
}) {
  const scheme = useColorScheme();
  const { halo, route } = PALETTE[scheme];
  const colors = DIFFICULTY_COLOR[scheme];
  const fitPoints = useMemo<LatLngTuple[]>(
    () => [...results.map((r): LatLngTuple => [r.coordinates[0].latitude, r.coordinates[0].longitude]), ...(me ? [me] : [])],
    [results, me],
  );
  const selected = results.find((r) => r.eventId === selectedId);

  return (
    <MapContainer
      center={me ?? DEFAULT_CENTER}
      zoom={me ? 11 : 6}
      zoomControl={false}
      style={{ height: "100%", width: "100%", minHeight: 240 }}
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <FitResults points={fitPoints} />
      <CenterTracker onCenter={onCenter} />
      {selected && (
        <Polyline
          positions={selected.coordinates.map((c): LatLngTuple => [c.latitude, c.longitude])}
          pathOptions={{ color: colors[selected.difficulty], weight: 5, lineCap: "round", lineJoin: "round" }}
        />
      )}
      {results.map((r) => {
        const isSelected = r.eventId === selectedId;
        return (
          <CircleMarker
            key={r.eventId}
            center={[r.coordinates[0].latitude, r.coordinates[0].longitude]}
            radius={isSelected ? 12 : 9}
            pathOptions={{ color: halo, weight: 3, fillColor: colors[r.difficulty], fillOpacity: 1 }}
            eventHandlers={{ click: () => onSelect(r.eventId) }}
          >
            <Tooltip direction="top">{r.name}</Tooltip>
          </CircleMarker>
        );
      })}
      {me && <CircleMarker center={me} radius={7} pathOptions={{ color: halo, weight: 3, fillColor: route, fillOpacity: 1 }} />}
    </MapContainer>
  );
}

export default ExploreMap;

import { useEffect, useMemo } from "react";
import {
  CircleMarker,
  MapContainer,
  Polyline,
  TileLayer,
  Tooltip,
  useMap,
  useMapEvents,
} from "react-leaflet";
import L, { type LatLngTuple } from "leaflet";
import "leaflet/dist/leaflet.css";
import type { GpsCoordinate } from "../interfaces/gps_coordinate";
import type { TrailSource, Waypoint } from "../interfaces/trail";
import { useColorScheme } from "../../../shared/theme/use_color_scheme";

const DEFAULT_CENTER: LatLngTuple = [41.9028, 12.4964];
const DEFAULT_ZOOM = 6;
const LIVE_ZOOM = 16;

const AMBER = "#F59E0B";

// Leaflet writes colours as SVG attributes, where CSS variables don't resolve.
export const PALETTE = {
  light: { ink: "#16201B", route: "#2F6FDB", brand: "#127A4B", halo: "#FFFFFF", alt: "#B45309" },
  dark: { ink: "#E8EDE9", route: "#6A9BF0", brand: "#4CC38A", halo: "#0F1512", alt: "#F59E0B" },
};

function FitBounds({ positions }: { positions: LatLngTuple[] }) {
  const map = useMap();
  useEffect(() => {
    if (positions.length > 0) {
      map.fitBounds(L.latLngBounds(positions), { padding: [24, 24] });
    }
  }, [map, positions]);
  return null;
}

/** Keeps the map centred on the live position while `follow` is on; reports manual panning. */
function Follow({
  current,
  follow,
  followKey,
  onUserMove,
}: {
  current: LatLngTuple;
  follow: boolean;
  followKey: number;
  onUserMove?: () => void;
}) {
  const map = useMap();
  useMapEvents({ dragstart: () => onUserMove?.() });
  useEffect(() => {
    if (follow) map.setView(current, Math.max(map.getZoom(), LIVE_ZOOM), { animate: true });
  }, [map, current, follow, followKey]);
  return null;
}

interface TrailMapProps {
  coordinates: GpsCoordinate[];
  waypoints?: Waypoint[];
  /** Line colour; imported trails are blue, recorded and planned trails green. */
  color?: TrailSource;
  /** Fit the whole trail in view. Turn off for live maps, which follow `current` instead. */
  fit?: boolean;
  /** The part of the trail already covered, drawn over it in a muted colour (tours). */
  completed?: GpsCoordinate[];
  /** A dashed line, e.g. from the live position back to the trail (tours). */
  guideLine?: GpsCoordinate[];
  /** Live position, drawn as a blue dot. */
  current?: GpsCoordinate | null;
  follow?: boolean;
  /** Change to re-centre on the live position. */
  followKey?: number;
  onUserMove?: () => void;
  className?: string;
}

function TrailMap({
  coordinates,
  waypoints = [],
  color = "recorded",
  fit = true,
  completed = [],
  guideLine = [],
  current,
  follow = false,
  followKey = 0,
  onUserMove,
  className,
}: TrailMapProps) {
  const { ink: INK, route: ROUTE, brand: BRAND, halo: HALO, alt: ALT } = PALETTE[useColorScheme()];
  const positions = useMemo<LatLngTuple[]>(
    () => coordinates.map((c) => [c.latitude, c.longitude]),
    [coordinates],
  );
  const start = positions[0];
  const end = positions[positions.length - 1];
  const currentPos: LatLngTuple | undefined = current ? [current.latitude, current.longitude] : undefined;
  const initial = currentPos ?? start ?? DEFAULT_CENTER;
  const line = color === "imported" ? ROUTE : BRAND;

  return (
    <MapContainer
      center={initial}
      zoom={currentPos ? LIVE_ZOOM : start ? 13 : DEFAULT_ZOOM}
      className={className}
      zoomControl={false}
      style={{ height: "100%", width: "100%", minHeight: 240 }}
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      {positions.length > 1 && (
        <Polyline positions={positions} pathOptions={{ color: line, weight: 5, lineCap: "round", lineJoin: "round" }} />
      )}
      {completed.length > 1 && (
        <Polyline
          positions={completed.map((c): LatLngTuple => [c.latitude, c.longitude])}
          pathOptions={{ color: INK, opacity: 0.4, weight: 5, lineCap: "round", lineJoin: "round" }}
        />
      )}
      {guideLine.length > 1 && (
        <Polyline
          positions={guideLine.map((c): LatLngTuple => [c.latitude, c.longitude])}
          pathOptions={{ color: ALT, weight: 4, dashArray: "2 9", lineCap: "round" }}
        />
      )}
      {start && (
        <CircleMarker center={start} radius={7} pathOptions={{ color: INK, weight: 3, fillColor: HALO, fillOpacity: 1 }} />
      )}
      {end && positions.length > 1 && !current && (
        <CircleMarker center={end} radius={7} pathOptions={{ color: HALO, weight: 3, fillColor: INK, fillOpacity: 1 }} />
      )}
      {waypoints.map((w, i) => (
        <CircleMarker
          key={i}
          center={[w.latitude, w.longitude]}
          radius={6}
          pathOptions={{ color: HALO, weight: 2, fillColor: AMBER, fillOpacity: 1 }}
        >
          <Tooltip>{w.name}</Tooltip>
        </CircleMarker>
      ))}
      {currentPos && (
        <>
          <CircleMarker center={currentPos} radius={20} pathOptions={{ stroke: false, fillColor: ROUTE, fillOpacity: 0.18 }} />
          <CircleMarker center={currentPos} radius={9} pathOptions={{ color: HALO, weight: 3, fillColor: ROUTE, fillOpacity: 1 }} />
          <Follow current={currentPos} follow={follow} followKey={followKey} onUserMove={onUserMove} />
        </>
      )}
      {fit && <FitBounds positions={positions} />}
    </MapContainer>
  );
}

export default TrailMap;

import { useEffect, useMemo } from "react";
import {
  MapContainer,
  Marker,
  Polyline,
  TileLayer,
  useMap,
} from "react-leaflet";
import L, { type LatLngTuple } from "leaflet";
import "leaflet/dist/leaflet.css";
import markerIcon from "leaflet/dist/images/marker-icon.png";
import markerIcon2x from "leaflet/dist/images/marker-icon-2x.png";
import markerShadow from "leaflet/dist/images/marker-shadow.png";
import type { Trail } from "../interfaces/trail";

// Leaflet's default marker icons break under bundlers; set them explicitly.
const defaultIcon = L.icon({
  iconUrl: markerIcon,
  iconRetinaUrl: markerIcon2x,
  shadowUrl: markerShadow,
  iconSize: [25, 41],
  iconAnchor: [12, 41],
});

const DEFAULT_CENTER: LatLngTuple = [41.9028, 12.4964];
const DEFAULT_ZOOM = 6;

function FitBounds({ positions }: { positions: LatLngTuple[] }) {
  const map = useMap();
  useEffect(() => {
    if (positions.length > 0) {
      map.fitBounds(L.latLngBounds(positions), { padding: [24, 24] });
    }
  }, [map, positions]);
  return null;
}

interface TrailMapProps {
  trail?: Trail;
  className?: string;
}

function TrailMap({ trail, className }: TrailMapProps) {
  const positions = useMemo<LatLngTuple[]>(
    () => (trail?.coordinates ?? []).map((c) => [c.latitude, c.longitude]),
    [trail],
  );

  const start = positions[0];
  const end = positions[positions.length - 1];

  return (
    <MapContainer
      center={start ?? DEFAULT_CENTER}
      zoom={start ? 13 : DEFAULT_ZOOM}
      className={className}
      style={{ height: "100%", width: "100%", minHeight: 300 }}
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      {positions.length > 0 && (
        <>
          <Polyline positions={positions} pathOptions={{ weight: 4 }} />
          <Marker position={start} icon={defaultIcon} />
          {positions.length > 1 && <Marker position={end} icon={defaultIcon} />}
          <FitBounds positions={positions} />
        </>
      )}
    </MapContainer>
  );
}

export default TrailMap;

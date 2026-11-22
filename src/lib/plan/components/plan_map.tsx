import { useEffect, useMemo, useRef } from "react";
import { CircleMarker, MapContainer, Marker, Polyline, TileLayer, useMap, useMapEvents } from "react-leaflet";
import L, { type LatLngTuple } from "leaflet";
import "leaflet/dist/leaflet.css";
import { useColorScheme } from "../../../shared/theme/use_color_scheme";
import { PALETTE } from "../../trail/components/trail_map";
import type { GpsCoordinate } from "../../trail/interfaces/gps_coordinate";
import type { RouteVariant, VariantKind } from "../route_planner";
import type { Checkpoint } from "../stores/plan_store";

const DEFAULT_CENTER: LatLngTuple = [41.9028, 12.4964];
const DEFAULT_ZOOM = 6;
/** Zoom used when centring on a point, close enough to see paths. */
export const LOCAL_ZOOM = 14;

/** A request to move the map. Change `key` to repeat the same move. */
export interface MapFocus {
  key: number;
  center: GpsCoordinate;
  zoom?: number;
  /** [[south, west], [north, east]]; fitted instead of `zoom` when given. */
  bounds?: [[number, number], [number, number]];
}

/** Line style per variant, matching the legend colours on the variant cards. */
const LINE: Record<VariantKind, { color: "brand" | "route" | "alt"; weight: number; dashArray?: string }> = {
  balanced: { color: "brand", weight: 5 },
  gentlest: { color: "route", weight: 4, dashArray: "10 6" },
  direct: { color: "alt", weight: 4, dashArray: "2 7" },
};

export function checkpointLabel(index: number): string {
  return index === 0 ? "S" : String(index + 1);
}

function pinIcon(label: string) {
  return L.divIcon({
    className: "plan-pin",
    html: `<span>${label}</span>`,
    iconSize: [32, 32],
    iconAnchor: [16, 16],
  });
}

function ClickToAdd({ onAdd }: { onAdd?: (p: GpsCoordinate) => void }) {
  useMapEvents({
    click: (e) => onAdd?.({ latitude: e.latlng.lat, longitude: e.latlng.lng }),
  });
  return null;
}

/** Fits the checkpoints/routes once on mount. */
function InitialView({ positions }: { positions: LatLngTuple[] }) {
  const map = useMap();
  const done = useRef(false);
  useEffect(() => {
    if (done.current) return;
    done.current = true;
    if (positions.length > 0) map.fitBounds(L.latLngBounds(positions), { padding: [32, 32], maxZoom: 15 });
  }, [map, positions]);
  return null;
}

function Focus({ focus }: { focus?: MapFocus | null }) {
  const map = useMap();
  useEffect(() => {
    if (!focus) return;
    if (focus.bounds) map.flyToBounds(focus.bounds, { padding: [24, 24], maxZoom: 16, duration: 0.8 });
    else map.flyTo([focus.center.latitude, focus.center.longitude], focus.zoom ?? Math.max(map.getZoom(), LOCAL_ZOOM), { duration: 0.8 });
    // Only a new key is a new request.
  }, [map, focus?.key]);
  return null;
}

/** Reports the map centre after each pan or zoom. */
function ViewReporter({ onChange }: { onChange?: (center: GpsCoordinate) => void }) {
  const map = useMapEvents({
    moveend: () => {
      const c = map.getCenter();
      onChange?.({ latitude: c.lat, longitude: c.lng });
    },
  });
  return null;
}

interface PlanMapProps {
  checkpoints: Checkpoint[];
  variants: RouteVariant[];
  /** Variant drawn on top and fully opaque. Others are drawn faded. */
  selectedId?: string | null;
  /** Show only the selected variant (the checkpoint screen). */
  onlySelected?: boolean;
  /** Point picked on the steepness profile. */
  cursor?: GpsCoordinate | null;
  /** The user's position, drawn as a blue dot. */
  position?: GpsCoordinate | null;
  /** A searched place, drawn as a ring so the user can tap it to add a checkpoint. */
  place?: GpsCoordinate | null;
  focus?: MapFocus | null;
  onViewChange?: (center: GpsCoordinate) => void;
  /** Tapping the map adds a checkpoint; markers can be dragged. Omit for a read-only map. */
  onAdd?: (p: GpsCoordinate) => void;
  onMove?: (id: string, p: GpsCoordinate) => void;
  className?: string;
}

function PlanMap({
  checkpoints, variants, selectedId, onlySelected, cursor, position, place, focus, onViewChange, onAdd, onMove, className,
}: PlanMapProps) {
  const palette = PALETTE[useColorScheme()];
  const editable = Boolean(onAdd);

  const lines = useMemo(() => {
    const shown = onlySelected ? variants.filter((v) => v.id === selectedId) : variants;
    // Selected last so it is drawn on top.
    return [...shown]
      .sort((a, b) => Number(a.id === selectedId) - Number(b.id === selectedId))
      .map((v) => ({
        id: v.id,
        style: LINE[v.kind],
        selected: v.id === selectedId,
        positions: v.coordinates.map((c): LatLngTuple => [c.latitude, c.longitude]),
      }));
  }, [variants, selectedId, onlySelected]);

  const initialPositions = useMemo<LatLngTuple[]>(
    () => [
      ...checkpoints.map((c): LatLngTuple => [c.latitude, c.longitude]),
      ...lines.flatMap((l) => l.positions),
    ],
    // Only the first render matters for the initial fit.
    [],
  );

  const icons = useMemo(() => checkpoints.map((_, i) => pinIcon(checkpointLabel(i))), [checkpoints]);

  return (
    <MapContainer
      center={DEFAULT_CENTER}
      zoom={DEFAULT_ZOOM}
      className={className}
      zoomControl={false}
      doubleClickZoom={!editable}
      style={{ height: "100%", width: "100%" }}
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      {lines.map((l) => (
        <Polyline
          key={l.id}
          positions={l.positions}
          pathOptions={{
            color: palette[l.style.color],
            weight: l.selected ? l.style.weight + 1 : l.style.weight,
            opacity: l.selected || onlySelected ? 1 : 0.55,
            dashArray: l.style.dashArray,
            lineCap: "round",
            lineJoin: "round",
          }}
        />
      ))}
      {checkpoints.map((c, i) => (
        <Marker
          key={c.id}
          position={[c.latitude, c.longitude]}
          icon={icons[i]}
          draggable={Boolean(onMove)}
          keyboard={false}
          eventHandlers={{
            dragend: (e) => {
              const { lat, lng } = (e.target as L.Marker).getLatLng();
              onMove?.(c.id, { latitude: lat, longitude: lng });
            },
          }}
        />
      ))}
      {place && (
        <CircleMarker
          center={[place.latitude, place.longitude]}
          radius={12}
          interactive={false}
          pathOptions={{ color: palette.ink, weight: 3, dashArray: "4 4", fillOpacity: 0 }}
        />
      )}
      {position && (
        <>
          <CircleMarker center={[position.latitude, position.longitude]} radius={18} interactive={false} pathOptions={{ stroke: false, fillColor: palette.route, fillOpacity: 0.18 }} />
          <CircleMarker center={[position.latitude, position.longitude]} radius={8} interactive={false} pathOptions={{ color: palette.halo, weight: 3, fillColor: palette.route, fillOpacity: 1 }} />
        </>
      )}
      {cursor && (
        <CircleMarker
          center={[cursor.latitude, cursor.longitude]}
          radius={7}
          interactive={false}
          pathOptions={{ color: palette.halo, weight: 3, fillColor: palette.ink, fillOpacity: 1 }}
        />
      )}
      <ClickToAdd onAdd={onAdd} />
      <InitialView positions={initialPositions} />
      <Focus focus={focus} />
      <ViewReporter onChange={onViewChange} />
    </MapContainer>
  );
}

export default PlanMap;

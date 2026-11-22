import { withDetail } from "../http/error_detail";
import { t } from "../i18n/i18n";
import type { GpsCoordinate } from "../../lib/trail/interfaces/gps_coordinate";
import type { Language } from "../i18n/translations";

/**
 * Place search through Photon (https://photon.komoot.io), komoot's free OpenStreetMap geocoder.
 * It allows search-as-you-type; the query and the map centre are sent to the server.
 */
const ENDPOINT = "https://photon.komoot.io/api/";

export type PlaceKind = "peak" | "settlement" | "nature" | "other";

export interface Place {
  id: string;
  name: string;
  kind: PlaceKind;
  /** "Capannori, Lucca, Italy" */
  context: string;
  latitude: number;
  longitude: number;
  /** [[south, west], [north, east]], for areas such as towns and parks. */
  bounds?: [[number, number], [number, number]];
}

interface PhotonFeature {
  geometry: { coordinates: [number, number] };
  properties: {
    osm_type: string;
    osm_id: number;
    osm_key: string;
    osm_value: string;
    name?: string;
    city?: string;
    county?: string;
    state?: string;
    country?: string;
    /** [minLon, maxLat, maxLon, minLat] */
    extent?: [number, number, number, number];
  };
}

const PEAKS = new Set(["peak", "volcano", "saddle", "ridge", "hill", "mountain_range"]);
const SETTLEMENTS = new Set(["city", "town", "village", "hamlet", "suburb", "locality", "isolated_dwelling"]);

function kindOf({ osm_key, osm_value }: PhotonFeature["properties"]): PlaceKind {
  if (osm_key === "natural" && PEAKS.has(osm_value)) return "peak";
  if (osm_key === "place" && SETTLEMENTS.has(osm_value)) return "settlement";
  if (osm_key === "natural" || osm_value === "nature_reserve" || osm_value === "national_park") return "nature";
  return "other";
}

/** Photon has no Italian labels; "default" gives local names, which is what Italian users expect. */
const PHOTON_LANG: Record<Language, string> = { en: "en", it: "default" };

export async function searchPlaces(
  query: string,
  { near, language, signal }: { near?: GpsCoordinate; language: Language; signal?: AbortSignal },
): Promise<Place[]> {
  const params = new URLSearchParams({ q: query, limit: "6", lang: PHOTON_LANG[language] });
  if (near) {
    params.set("lat", near.latitude.toFixed(4));
    params.set("lon", near.longitude.toFixed(4));
  }

  let response: Response;
  try {
    response = await fetch(`${ENDPOINT}?${params}`, { signal });
  } catch (e) {
    if (signal?.aborted) throw e;
    throw new Error(t("search.error.offline"));
  }
  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new Error(withDetail(t("search.error.server", { status: response.status }), body));
  }

  const json = (await response.json()) as { features?: PhotonFeature[] };
  return (json.features ?? [])
    .filter((f) => f.properties.name)
    .map((f) => {
      const p = f.properties;
      const [longitude, latitude] = f.geometry.coordinates;
      const context = [p.city, p.county, p.country].filter((part) => part && part !== p.name);
      return {
        id: `${p.osm_type}${p.osm_id}`,
        name: p.name!,
        kind: kindOf(p),
        context: [...new Set(context)].join(", "),
        latitude,
        longitude,
        ...(p.extent && {
          bounds: [
            [p.extent[3], p.extent[0]],
            [p.extent[1], p.extent[2]],
          ] as Place["bounds"],
        }),
      };
    });
}

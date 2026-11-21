import type { GpsCoordinate } from "../../lib/trail/interfaces/gps_coordinate";
import type { Trail, Waypoint } from "../../lib/trail/interfaces/trail";

export interface ParsedTrack {
  format: "GPX" | "KML";
  /** Name found in the file's metadata, if any. */
  name?: string;
  segments: GpsCoordinate[][];
  waypoints: Waypoint[];
}

function parseXml(text: string): Document {
  const doc = new DOMParser().parseFromString(text, "application/xml");
  if (doc.querySelector("parsererror")) throw new Error("This file is not valid XML.");
  return doc;
}

/** Direct-or-nested elements by local name, ignoring XML namespaces. */
function all(root: Document | Element, name: string): Element[] {
  return Array.from(root.getElementsByTagNameNS("*", name));
}

function childText(el: Element, name: string): string | undefined {
  const child = Array.from(el.children).find((c) => c.localName === name);
  return child?.textContent?.trim() || undefined;
}

function num(value: string | null | undefined): number | undefined {
  if (value === null || value === undefined || value === "") return undefined;
  const n = Number(value);
  return Number.isFinite(n) ? n : undefined;
}

function toIso(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const t = Date.parse(value);
  return Number.isNaN(t) ? undefined : new Date(t).toISOString();
}

function parseGpxPoint(el: Element): GpsCoordinate | null {
  const latitude = num(el.getAttribute("lat"));
  const longitude = num(el.getAttribute("lon"));
  if (latitude === undefined || longitude === undefined) return null;
  const altitude = num(childText(el, "ele"));
  const timestamp = toIso(childText(el, "time"));
  return {
    latitude,
    longitude,
    ...(altitude !== undefined && { altitude }),
    ...(timestamp && { timestamp }),
  };
}

function parseGpx(doc: Document): ParsedTrack {
  const trks = all(doc, "trk");
  // A route (<rte>) is the fallback for files that carry no recorded track.
  const lines = trks.length > 0 ? trks.flatMap((t) => all(t, "trkseg")) : all(doc, "rte");
  const pointTag = trks.length > 0 ? "trkpt" : "rtept";
  const segments = lines
    .map((line) =>
      all(line, pointTag)
        .map(parseGpxPoint)
        .filter((p): p is GpsCoordinate => p !== null),
    )
    .filter((s) => s.length > 0);

  const waypoints = all(doc, "wpt")
    .map((el, i) => {
      const p = parseGpxPoint(el);
      return p && { ...p, name: childText(el, "name") ?? `Waypoint ${i + 1}` };
    })
    .filter((w): w is Waypoint => w !== null);

  const metaName = all(doc, "metadata")
    .map((m) => childText(m, "name"))
    .find(Boolean);
  const name = metaName ?? (trks[0] && childText(trks[0], "name"));
  return { format: "GPX", name, segments, waypoints };
}

function parseKmlCoordinates(text: string): GpsCoordinate[] {
  return text
    .trim()
    .split(/\s+/)
    .map((triplet) => {
      const [lon, lat, alt] = triplet.split(",").map(Number);
      if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
      return { latitude: lat, longitude: lon, ...(Number.isFinite(alt) && { altitude: alt }) };
    })
    .filter((p): p is GpsCoordinate => p !== null);
}

function parseKml(doc: Document): ParsedTrack {
  const segments: GpsCoordinate[][] = [];
  const waypoints: Waypoint[] = [];
  const placemarks = all(doc, "Placemark");

  placemarks.forEach((pm, i) => {
    for (const line of all(pm, "LineString")) {
      const coords = parseKmlCoordinates(childText(line, "coordinates") ?? "");
      if (coords.length > 0) segments.push(coords);
    }
    // Google Earth exports timed tracks as <gx:Track> with parallel <when>/<gx:coord> lists.
    for (const track of all(pm, "Track")) {
      const whens = all(track, "when").map((w) => toIso(w.textContent?.trim()));
      const coords = all(track, "coord")
        .map((c, j) => {
          const [lon, lat, alt] = (c.textContent ?? "").trim().split(/\s+/).map(Number);
          if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
          return {
            latitude: lat,
            longitude: lon,
            ...(Number.isFinite(alt) && { altitude: alt }),
            ...(whens[j] && { timestamp: whens[j] }),
          };
        })
        .filter((p): p is GpsCoordinate => p !== null);
      if (coords.length > 0) segments.push(coords);
    }
    for (const point of all(pm, "Point")) {
      const [p] = parseKmlCoordinates(childText(point, "coordinates") ?? "");
      if (p) waypoints.push({ ...p, name: childText(pm, "name") ?? `Waypoint ${i + 1}` });
    }
  });

  const trackPlacemark = placemarks.find(
    (pm) => all(pm, "LineString").length > 0 || all(pm, "Track").length > 0,
  );
  const name = trackPlacemark && childText(trackPlacemark, "name");
  return { format: "KML", name, segments, waypoints };
}

/** Parses the text of a .gpx or .kml file. Throws an Error with a user-readable message. */
export function parseTrackFile(text: string, filename: string): ParsedTrack {
  const doc = parseXml(text);
  const root = doc.documentElement.localName.toLowerCase();
  let parsed: ParsedTrack;
  if (root === "gpx") parsed = parseGpx(doc);
  else if (root === "kml") parsed = parseKml(doc);
  else throw new Error(`"${filename}" is not a GPX or KML file.`);
  if (parsed.segments.length === 0) throw new Error("No track points were found in this file.");
  return parsed;
}

function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function gpxPoint(tag: string, p: GpsCoordinate, name?: string): string {
  const inner = [
    name !== undefined && `<name>${esc(name)}</name>`,
    p.altitude !== undefined && `<ele>${p.altitude}</ele>`,
    p.timestamp && `<time>${p.timestamp}</time>`,
  ]
    .filter(Boolean)
    .join("");
  return `<${tag} lat="${p.latitude}" lon="${p.longitude}">${inner}</${tag}>`;
}

export function buildGpx(trail: Trail): string {
  const waypoints = trail.waypoints.map((w) => `  ${gpxPoint("wpt", w, w.name)}`).join("\n");
  const points = trail.coordinates.map((c) => `      ${gpxPoint("trkpt", c)}`).join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="pania" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>${esc(trail.name)}</name>${trail.description ? `<desc>${esc(trail.description)}</desc>` : ""}</metadata>
${waypoints}
  <trk>
    <name>${esc(trail.name)}</name>
    <trkseg>
${points}
    </trkseg>
  </trk>
</gpx>
`;
}

function gpxFile(trail: Trail): File {
  const safeName = trail.name.replace(/[^\p{L}\p{N}]+/gu, "-").replace(/^-|-$/g, "") || "trail";
  return new File([buildGpx(trail)], `${safeName}.gpx`, { type: "application/gpx+xml" });
}

function download(file: File) {
  const url = URL.createObjectURL(file);
  const a = document.createElement("a");
  a.href = url;
  a.download = file.name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

/** Saves the trail as a .gpx file. */
export function exportGpx(trail: Trail): void {
  download(gpxFile(trail));
}

/** Opens the system share sheet with the .gpx file, falling back to a download. */
export async function shareGpx(trail: Trail): Promise<void> {
  const file = gpxFile(trail);
  if (navigator.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file], title: trail.name });
    } catch (e) {
      if (e instanceof DOMException && e.name === "AbortError") return; // user dismissed the sheet
      download(file);
    }
    return;
  }
  download(file);
}

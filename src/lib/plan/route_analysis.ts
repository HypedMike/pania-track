import { haversine } from "../../shared/gps/trail_stats";
import type { RoutedPath, WaySegment } from "../../shared/routing/brouter";

/**
 * Italian CAI difficulty grades, the scale used on trail signs in Italy:
 * T (tourist, easy), E (hiking), EE (expert hikers), EEA (equipped / alpine).
 */
export type Difficulty = "T" | "E" | "EE" | "EEA";
const GRADES: Difficulty[] = ["T", "E", "EE", "EEA"];

export type HazardKind = "demanding" | "faint" | "busyRoad" | "steep" | "ferry";

export interface Hazard {
  kind: HazardKind;
  /** Length of the affected stretch, in meters (for `steep`: the steepest grade, in %). */
  value: number;
}

export interface RouteAnalysis {
  distanceM: number;
  gainM: number;
  lossM: number;
  /** Steepest grade sustained over ~200 m, in percent. */
  maxSlopePct: number;
  /** Share of the distance on waymarked hiking routes, 0–1. */
  markedShare: number;
  /** Meters on roads open to traffic. */
  roadM: number;
  /** Meters on busy roads (primary, secondary, trunk). */
  busyRoadM: number;
  /** Meters on ferry lines, which the router uses when a checkpoint is off the coast. */
  ferryM: number;
  difficulty: Difficulty;
  /** Estimated walking time (DIN 33466), in milliseconds. */
  estimatedMs: number;
  hazards: Hazard[];
}

/** Altitude changes below this are treated as noise, as in trail_stats. */
const ELEVATION_NOISE_M = 3;
/**
 * Grades are measured over at least this distance. The router's elevation model has ~90 m
 * cells, so shorter windows mostly measure noise.
 */
const SLOPE_WINDOW_M = 200;
/** Sustained grade that alone makes a route EE, and that gets a warning. */
const EXPERT_SLOPE_PCT = 40;
const STEEP_WARNING_PCT = 35;
/** Stretches shorter than this don't change the grade or raise a warning. */
const MIN_STRETCH_M = 50;

const ROADS = new Set([
  "motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential",
  "living_street", "service", "road",
  "trunk_link", "primary_link", "secondary_link", "tertiary_link",
]);
const BUSY_ROADS = new Set(["trunk", "primary", "secondary", "trunk_link", "primary_link", "secondary_link"]);

/** OSM sac_scale → CAI grade. */
const SAC_TO_CAI: Record<string, Difficulty> = {
  hiking: "T",
  mountain_hiking: "E",
  demanding_mountain_hiking: "EE",
  alpine_hiking: "EEA",
  demanding_alpine_hiking: "EEA",
  difficult_alpine_hiking: "EEA",
};

function harder(a: Difficulty, b: Difficulty): Difficulty {
  return GRADES.indexOf(a) >= GRADES.indexOf(b) ? a : b;
}

function gainAndLoss(alts: number[]): { gainM: number; lossM: number } {
  let gainM = 0;
  let lossM = 0;
  let ref = alts[0];
  for (const alt of alts) {
    if (alt - ref >= ELEVATION_NOISE_M) {
      gainM += alt - ref;
      ref = alt;
    } else if (ref - alt >= ELEVATION_NOISE_M) {
      lossM += ref - alt;
      ref = alt;
    }
  }
  return { gainM, lossM };
}

function maxSlope(path: RoutedPath): number {
  const pts = path.coordinates.filter((c) => c.altitude !== undefined);
  const cum = [0];
  for (let i = 1; i < pts.length; i++) cum.push(cum[i - 1] + haversine(pts[i - 1], pts[i]));
  let max = 0;
  let j = 0;
  for (let i = 0; i < pts.length; i++) {
    while (j < pts.length && cum[j] - cum[i] < SLOPE_WINDOW_M) j++;
    if (j >= pts.length) break;
    const slope = Math.abs(pts[j].altitude! - pts[i].altitude!) / (cum[j] - cum[i]);
    if (slope > max) max = slope;
  }
  return max * 100;
}

function slopeGrade(pct: number): Difficulty {
  if (pct >= EXPERT_SLOPE_PCT) return "EE";
  if (pct >= 15) return "E";
  return "T";
}

const isRoad = (s: WaySegment) => ROADS.has(s.tags.highway) && s.tags.foot !== "designated";
const isMarked = (s: WaySegment) => Object.keys(s.tags).some((k) => k.startsWith("route_hiking_"));
const isFaint = (s: WaySegment) => ["bad", "horrible", "no"].includes(s.tags.trail_visibility);
const isDemanding = (s: WaySegment) => {
  const grade = SAC_TO_CAI[s.tags.sac_scale];
  return grade === "EE" || grade === "EEA";
};

function sum(segments: WaySegment[], test: (s: WaySegment) => boolean): number {
  return segments.reduce((total, s) => total + (test(s) ? s.distanceM : 0), 0);
}

/** DIN 33466: 4 km/h on the flat, 300 m/h up, 500 m/h down; the smaller part counts half. */
function walkingTimeMs(distanceM: number, gainM: number, lossM: number): number {
  const horizontalH = distanceM / 4000;
  const verticalH = gainM / 300 + lossM / 500;
  const hours = Math.max(horizontalH, verticalH) + Math.min(horizontalH, verticalH) / 2;
  return hours * 3_600_000;
}

export function analyzeRoute(path: RoutedPath): RouteAnalysis {
  const { coordinates, segments } = path;
  let distanceM = 0;
  for (let i = 1; i < coordinates.length; i++) distanceM += haversine(coordinates[i - 1], coordinates[i]);
  const alts = coordinates.map((c) => c.altitude).filter((a): a is number => a !== undefined);
  const { gainM, lossM } = alts.length > 0 ? gainAndLoss(alts) : { gainM: 0, lossM: 0 };
  const maxSlopePct = maxSlope(path);

  const segmentTotal = sum(segments, () => true) || distanceM || 1;
  const markedShare = sum(segments, isMarked) / segmentTotal;
  const roadM = sum(segments, isRoad);
  const busyRoadM = sum(segments, (s) => BUSY_ROADS.has(s.tags.highway));
  const demandingM = sum(segments, isDemanding);
  const faintM = sum(segments, isFaint);
  const ferryM = sum(segments, (s) => s.tags.route === "ferry");

  let difficulty = slopeGrade(maxSlopePct);
  for (const s of segments) {
    const grade = SAC_TO_CAI[s.tags.sac_scale];
    if (grade && s.distanceM >= MIN_STRETCH_M) difficulty = harder(difficulty, grade);
  }

  const hazards: Hazard[] = [];
  if (demandingM >= MIN_STRETCH_M) hazards.push({ kind: "demanding", value: demandingM });
  if (ferryM > 0) hazards.push({ kind: "ferry", value: ferryM });
  if (maxSlopePct >= STEEP_WARNING_PCT) hazards.push({ kind: "steep", value: maxSlopePct });
  if (faintM >= MIN_STRETCH_M) hazards.push({ kind: "faint", value: faintM });
  if (busyRoadM >= 200) hazards.push({ kind: "busyRoad", value: busyRoadM });

  return {
    distanceM,
    gainM,
    lossM,
    maxSlopePct,
    markedShare,
    roadM,
    busyRoadM,
    ferryM,
    difficulty,
    estimatedMs: walkingTimeMs(distanceM, gainM, lossM),
    hazards,
  };
}

const DIFFICULTY_PENALTY: Record<Difficulty, number> = { T: 0, E: 0.1, EE: 0.5, EEA: 1 };

/**
 * Lower is better. Distance, weighted up by how risky the route is: harder grades, faint
 * trails and busy roads cost extra, and so do roads in general when the user avoids them.
 * This is what makes the recommended route "the shortest of the safe ones".
 */
export function routeCost(a: RouteAnalysis, avoidRoads: boolean): number {
  const d = a.distanceM || 1;
  const risk =
    DIFFICULTY_PENALTY[a.difficulty] +
    (a.busyRoadM / d) * 1.5 +
    (a.ferryM / d) * 5 +
    (a.hazards.find((h) => h.kind === "faint")?.value ?? 0) / d * 0.5 +
    (a.roadM / d) * (avoidRoads ? 0.6 : 0.05) +
    (1 - a.markedShare) * 0.1;
  return d * (1 + risk);
}

import { fetchRoute, type RoutingProfile } from "../../shared/routing/brouter";
import type { GpsCoordinate } from "../trail/interfaces/gps_coordinate";
import { analyzeRoute, routeCost, type RouteAnalysis } from "./route_analysis";

/** Why a variant is offered. `balanced` is the recommended shortest-and-safest route. */
export type VariantKind = "balanced" | "gentlest" | "direct";

export interface RouteVariant {
  id: string;
  /** Display letter: A, B, C. */
  letter: string;
  kind: VariantKind;
  coordinates: GpsCoordinate[];
  analysis: RouteAnalysis;
}

/** Requests sent for every plan. BRouter's alternatives are other good paths for the same profile. */
const REQUESTS: { profile: RoutingProfile; alternative: number; roads: boolean }[] = [
  { profile: "hiking-mountain", alternative: 0, roads: false },
  { profile: "hiking-mountain", alternative: 1, roads: false },
  { profile: "hiking-mountain", alternative: 2, roads: false },
  { profile: "shortest", alternative: 0, roads: true },
];

/** A gentler or more direct variant has to differ by at least this much to be worth showing. */
const MIN_SLOPE_GAIN_PCT = 2;
const MIN_DISTANCE_SAVING = 0.03;

interface Candidate {
  coordinates: GpsCoordinate[];
  analysis: RouteAnalysis;
}

function sameRoute(a: Candidate, b: Candidate): boolean {
  return (
    Math.abs(a.analysis.distanceM - b.analysis.distanceM) < Math.max(30, a.analysis.distanceM * 0.01) &&
    Math.abs(a.analysis.gainM - b.analysis.gainM) < 10
  );
}

/**
 * Routes through the checkpoints with several strategies and picks up to three variants:
 * the recommended one (shortest weighed by safety), the gentlest, and the most direct.
 * Rejects only if no request succeeds.
 */
export async function planRoutes(
  checkpoints: GpsCoordinate[],
  { loop, avoidRoads }: { loop: boolean; avoidRoads: boolean },
  signal?: AbortSignal,
): Promise<RouteVariant[]> {
  const points = loop && checkpoints.length > 1 ? [...checkpoints, checkpoints[0]] : checkpoints;
  const requests = REQUESTS.filter((r) => !(avoidRoads && r.roads));
  const results = await Promise.allSettled(
    requests.map((r) => fetchRoute(points, r.profile, r.alternative, signal)),
  );
  if (signal?.aborted) throw new DOMException("Aborted", "AbortError");

  const candidates: Candidate[] = [];
  for (const result of results) {
    if (result.status !== "fulfilled" || result.value.coordinates.length < 2) continue;
    const candidate = { coordinates: result.value.coordinates, analysis: analyzeRoute(result.value) };
    if (!candidates.some((c) => sameRoute(c, candidate))) candidates.push(candidate);
  }
  if (candidates.length === 0) {
    const failure = results.find((r): r is PromiseRejectedResult => r.status === "rejected");
    throw failure?.reason ?? new Error("No route");
  }

  const byCost = [...candidates].sort((a, b) => routeCost(a.analysis, avoidRoads) - routeCost(b.analysis, avoidRoads));
  const [best, ...rest] = byCost;
  const picked: { kind: VariantKind; candidate: Candidate }[] = [{ kind: "balanced", candidate: best }];

  const gentlest = [...rest].sort((a, b) => a.analysis.maxSlopePct - b.analysis.maxSlopePct)[0];
  if (gentlest && gentlest.analysis.maxSlopePct <= best.analysis.maxSlopePct - MIN_SLOPE_GAIN_PCT) {
    picked.push({ kind: "gentlest", candidate: gentlest });
  }

  const direct = rest
    .filter((c) => !picked.some((p) => p.candidate === c))
    .sort((a, b) => a.analysis.distanceM - b.analysis.distanceM)[0];
  if (direct && direct.analysis.distanceM <= best.analysis.distanceM * (1 - MIN_DISTANCE_SAVING)) {
    picked.push({ kind: "direct", candidate: direct });
  }

  return picked.map(({ kind, candidate }, i) => ({
    id: kind,
    letter: String.fromCharCode(65 + i),
    kind,
    ...candidate,
  }));
}

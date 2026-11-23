import { describe, expect, it } from "vitest";
import type { HourForecast } from "../../shared/weather/open_meteo";
import { at, line } from "./test_helpers";
import {
  BIKE_SPEED_MS,
  FOOT_SPEED_MS,
  assessWeather,
  averageSpeedMs,
  chooseSpeedMs,
  computeGuidance,
  computeWarnings,
  plannedSpeedMs,
  recentSpeedMs,
} from "./tour_guidance";
import { buildTrackIndex, pointAtDistance } from "./track_progress";

const coords = line([0, 0], [1000, 0], [1000, 1000]);
const index = buildTrackIndex(coords);

describe("speed", () => {
  const samples = [
    { time: 0, alongM: 0 },
    { time: 60_000, alongM: 90 },
    { time: 120_000, alongM: 180 },
  ];
  it("measures recent progress", () => {
    expect(recentSpeedMs(samples, 120_000)).toBeCloseTo(1.5, 5);
  });
  it("needs enough time to say anything", () => {
    expect(recentSpeedMs([{ time: 0, alongM: 0 }, { time: 10_000, alongM: 30 }], 10_000)).toBeNull();
    expect(recentSpeedMs([], 0)).toBeNull();
  });
  it("only looks at the last few minutes", () => {
    const old = [{ time: 0, alongM: 0 }, { time: 60_000, alongM: 500 }, ...samples.map((s) => ({ time: s.time + 600_000, alongM: s.alongM + 500 }))];
    expect(recentSpeedMs(old, 720_000)).toBeCloseTo(1.5, 5);
  });
  it("never reports going backwards", () => {
    expect(recentSpeedMs([{ time: 0, alongM: 100 }, { time: 60_000, alongM: 40 }], 60_000)).toBe(0);
  });
  it("averages since the start, after a minute", () => {
    expect(averageSpeedMs({ time: 0, alongM: 0 }, { time: 100_000, alongM: 120 })).toBeCloseTo(1.2, 5);
    expect(averageSpeedMs({ time: 0, alongM: 0 }, { time: 30_000, alongM: 100 })).toBeNull();
    expect(averageSpeedMs(null, null)).toBeNull();
  });
  it("prefers live, then average, then plan", () => {
    expect(chooseSpeedMs(1.4, 1.0, 1.1)).toBe(1.4);
    expect(chooseSpeedMs(0.1, 1.0, 1.1)).toBe(1.0);
    expect(chooseSpeedMs(null, null, 1.1)).toBe(1.1);
    expect(chooseSpeedMs(0.1, 0.2, 1.1)).toBe(1.1);
  });
});

describe("plannedSpeedMs", () => {
  it("walks flat ground at 4 km/h and rides at 14", () => {
    expect(plannedSpeedMs(coords, "foot")).toBeCloseTo(FOOT_SPEED_MS, 3);
    expect(plannedSpeedMs(coords, "bike")).toBeCloseTo(BIKE_SPEED_MS, 3);
  });
  it("is slower uphill (Naismith)", () => {
    const climb = coords.map((c, i) => ({ ...c, altitude: i * 5 }));
    expect(plannedSpeedMs(climb, "foot")).toBeLessThan(FOOT_SPEED_MS * 0.8);
  });
  it("uses the recorded pace when the trail has timestamps", () => {
    const timed = coords.map((c, i) => ({ ...c, timestamp: new Date(i * 10_000).toISOString() })); // 1 m/s
    expect(plannedSpeedMs(timed, "foot")).toBeCloseTo(1, 1);
  });
  it("ignores an implausible recorded pace", () => {
    const fast = coords.map((c, i) => ({ ...c, timestamp: new Date(i * 100).toISOString() })); // 100 m/s
    expect(plannedSpeedMs(fast, "foot")).toBeCloseTo(FOOT_SPEED_MS, 3);
  });
});

function guide(position = at(300, 0), over: Partial<Parameters<typeof computeGuidance>[0]> = {}) {
  return computeGuidance({ index, waypoints: [], position, speedMs: 1, nowMs: 0, offTrackThresholdM: 50, ...over });
}

describe("computeGuidance", () => {
  it("reports progress and remaining distance", () => {
    const g = guide();
    expect(g.alongM).toBeCloseTo(300, 0);
    expect(g.remainingM).toBeCloseTo(index.totalM - 300, 0);
    expect(g.progressPct).toBeCloseTo((300 / index.totalM) * 100, 0);
  });
  it("estimates arrival from the speed", () => {
    const g = guide(at(300, 0), { speedMs: 2, nowMs: 1_000 });
    expect(g.etaMs).toBeCloseTo(1_000 + (g.remainingM / 2) * 1000, -1);
  });
  it("does not divide by zero when standing still", () => {
    expect(Number.isFinite(guide(at(300, 0), { speedMs: 0 }).etaMs)).toBe(true);
  });
  it("points along the trail when on it", () => {
    const g = guide();
    expect(g.bearing < 3 || g.bearing > 357).toBe(true);
    expect(g.turn).toBeNull();
  });
  it("announces the turn", () => {
    expect(guide(at(850, 0)).turn?.direction).toBe("right");
  });
  it("points back to the trail when off it, and announces no turn", () => {
    const g = guide(at(500, -100));
    expect(g.offTrackM).toBeCloseTo(100, 0);
    expect(g.bearing).toBeGreaterThan(60);
    expect(g.bearing).toBeLessThan(110);
    expect(g.turn).toBeNull();
  });
  it("is arrived within 30 m of the end, on the trail only", () => {
    expect(guide(pointAtDistance(index, index.totalM - 10)).arrived).toBe(true);
    expect(guide(at(1000, 1000 - 5 + 0)).arrived).toBe(true);
    expect(guide(at(1100, 1000)).arrived).toBe(false); // 100 m off, even if near the end
    expect(guide().arrived).toBe(false);
  });
  it("finds the next waypoint ahead, not the ones passed", () => {
    const waypoints = [
      { ...at(100, 0), name: "behind" },
      { ...at(1000, 400), name: "ahead" },
    ];
    const g = guide(at(300, 0), { waypoints });
    expect(g.nextWaypoint?.name).toBe("ahead");
    expect(g.nextWaypoint?.inM).toBeCloseTo(1100, -1);
    expect(guide(at(1000, 900), { waypoints }).nextWaypoint).toBeNull();
  });
});

const hour = (h: number, over: Partial<HourForecast> = {}): HourForecast => ({
  time: h * 3_600_000,
  temperatureC: 15,
  precipProbPct: 0,
  precipMm: 0,
  code: 1,
  gustKmh: 10,
  ...over,
});
const kinds = (ws: { kind: string }[]) => ws.map((w) => w.kind);

describe("assessWeather", () => {
  it("is quiet in good weather", () => {
    expect(assessWeather([hour(0), hour(1)], 0, 7_200_000)).toEqual([]);
  });
  it("only looks at the hours of the trip", () => {
    expect(assessWeather([hour(5, { code: 95 })], 0, 3_600_000)).toEqual([]);
  });
  it("warns of thunderstorms as danger, and drops rain then", () => {
    const w = assessWeather([hour(0, { code: 95, precipProbPct: 90, precipMm: 5 })], 0, 3_600_000);
    expect(kinds(w)).toEqual(["storm"]);
    expect(w[0].level).toBe("danger");
  });
  it("needs both probability and amount for rain", () => {
    expect(assessWeather([hour(0, { precipProbPct: 90, precipMm: 0.1 })], 0, 3_600_000)).toEqual([]);
    expect(assessWeather([hour(0, { precipProbPct: 20, precipMm: 3 })], 0, 3_600_000)).toEqual([]);
    expect(kinds(assessWeather([hour(0, { precipProbPct: 70, precipMm: 1 })], 0, 3_600_000))).toEqual(["rain"]);
  });
  it("calls heavy rain danger", () => {
    expect(assessWeather([hour(0, { precipProbPct: 90, precipMm: 6 })], 0, 3_600_000)[0].level).toBe("danger");
  });
  it("reports snow, wind, heat and frost", () => {
    expect(kinds(assessWeather([hour(0, { code: 73 })], 0, 3_600_000))).toEqual(["snow"]);
    const wind = assessWeather([hour(0, { gustKmh: 95 })], 0, 3_600_000);
    expect(wind[0]).toMatchObject({ kind: "wind", level: "danger", data: { kmh: 95 } });
    expect(kinds(assessWeather([hour(0, { temperatureC: 35 })], 0, 3_600_000))).toEqual(["heat"]);
    expect(kinds(assessWeather([hour(0, { temperatureC: -3 })], 0, 3_600_000))).toEqual(["cold"]);
  });
  it("dates a warning from now when the hour is already under way", () => {
    const w = assessWeather([hour(0, { code: 95 })], 1_800_000, 3_600_000);
    expect(w[0].data.atMs).toBe(1_800_000);
  });
});

describe("computeWarnings", () => {
  // 14:30 UTC on 23 Nov 2026 in the Alps: sunset is about 15:38 UTC.
  const now = Date.UTC(2026, 10, 23, 14, 30);
  const base = () => {
    const guidance = computeGuidance({ index, waypoints: [], position: at(300, 0), speedMs: 1.2, nowMs: now, offTrackThresholdM: 50 });
    return {
      guidance,
      offTrack: false,
      nowMs: now,
      lastFixMs: now,
      targetArrivalMs: null as number | null,
      position: at(300, 0),
      destination: coords[coords.length - 1],
      forecast: [] as HourForecast[],
    };
  };
  const speedy = (input: ReturnType<typeof base>, speedMs: number) => ({
    ...input,
    guidance: computeGuidance({ index, waypoints: [], position: input.position, speedMs, nowMs: now, offTrackThresholdM: 50 }),
  });

  it("has nothing to say when all is well", () => {
    // 1.7 km at 1.2 m/s ends well before sunset
    expect(computeWarnings(base())).toEqual([]);
  });
  it("reports being off the trail first", () => {
    const w = computeWarnings({ ...base(), offTrack: true });
    expect(w[0]).toMatchObject({ kind: "offTrack", level: "danger" });
  });
  it("reports lost GPS", () => {
    expect(kinds(computeWarnings({ ...base(), lastFixMs: now - 90_000 }))).toEqual(["noGps"]);
    expect(computeWarnings({ ...base(), lastFixMs: now - 30_000 })).toEqual([]);
  });
  it("warns when late for the target, with the pace needed", () => {
    const w = computeWarnings({ ...base(), targetArrivalMs: now + 10 * 60_000 }).find((x) => x.kind === "late")!;
    expect(w.data.neededSpeedMs).toBeGreaterThan(2);
    expect(w.data.lateByMs).toBeGreaterThan(0);
  });
  it("tolerates five minutes of lateness", () => {
    const input = base();
    const target = input.guidance.etaMs - 4 * 60_000;
    expect(kinds(computeWarnings({ ...input, targetArrivalMs: target }))).not.toContain("late");
  });
  it("still reports lateness when the target has passed, without a needed pace", () => {
    const w = computeWarnings({ ...base(), targetArrivalMs: now - 60_000 }).find((x) => x.kind === "late")!;
    expect(w.data.neededSpeedMs).toBe(0);
  });
  it("warns when the arrival is after sunset", () => {
    const w = computeWarnings(speedy(base(), 0.3));
    expect(kinds(w)).toContain("afterDark");
  });
  it("says when it is already dark", () => {
    const night = Date.UTC(2026, 10, 23, 19, 0);
    const input = { ...base(), nowMs: night, lastFixMs: night };
    expect(kinds(computeWarnings(input))).toContain("dark");
  });
  it("adds weather for the time of the trip", () => {
    const forecast = [hour(Math.floor(now / 3_600_000), { code: 95 })];
    expect(kinds(computeWarnings({ ...base(), forecast }))).toContain("storm");
  });
  it("puts danger before warning", () => {
    const forecast = [hour(Math.floor(now / 3_600_000), { code: 95, temperatureC: -2 })];
    const w = computeWarnings({ ...base(), forecast });
    expect(w[0].level).toBe("danger");
  });
  it("stops warning about the future once arrived", () => {
    const end = pointAtDistance(index, index.totalM - 5);
    const guidance = computeGuidance({ index, waypoints: [], position: { ...end }, speedMs: 0.3, nowMs: now, offTrackThresholdM: 50 });
    const forecast = [hour(Math.floor(now / 3_600_000), { code: 95 })];
    expect(computeWarnings({ ...base(), guidance, position: end, forecast, targetArrivalMs: now - 1 })).toEqual([]);
  });
});

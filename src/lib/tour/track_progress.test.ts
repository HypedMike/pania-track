import { describe, expect, it } from "vitest";
import { at, line } from "./test_helpers";
import {
  bearingDeg,
  bearingDelta,
  buildTrackIndex,
  compassPoint,
  nextTurn,
  pointAtDistance,
  projectOnTrack,
  trackUpTo,
} from "./track_progress";

// 1 km north, then 1 km east.
const L = buildTrackIndex(line([0, 0], [1000, 0], [1000, 1000]));
// 1 km north and straight back down the same way.
const OAB = buildTrackIndex(line([0, 0], [1000, 0], [0, 0]));

describe("buildTrackIndex", () => {
  it("measures the trail", () => {
    expect(L.totalM).toBeCloseTo(2000, -1);
    expect(L.cumulativeM[0]).toBe(0);
  });
  it("copes with an empty trail", () => {
    expect(buildTrackIndex([]).totalM).toBe(0);
  });
});

describe("bearings", () => {
  it("gives compass bearings", () => {
    expect(bearingDeg(at(0), at(100))).toBeCloseTo(0, 0);
    expect(bearingDeg(at(0), at(0, 100))).toBeCloseTo(90, 0);
    expect(bearingDeg(at(0), at(-100))).toBeCloseTo(180, 0);
    expect(bearingDeg(at(0), at(0, -100))).toBeCloseTo(270, 0);
  });
  it("takes the short way round", () => {
    expect(bearingDelta(350, 10)).toBe(20);
    expect(bearingDelta(10, 350)).toBe(-20);
    expect(bearingDelta(0, 180)).toBe(180);
  });
  it("names compass points", () => {
    expect(compassPoint(0)).toBe("N");
    expect(compassPoint(359)).toBe("N");
    expect(compassPoint(100)).toBe("E");
    expect(compassPoint(225)).toBe("SW");
  });
});

describe("pointAtDistance", () => {
  it("interpolates and clamps", () => {
    const p = pointAtDistance(L, 500);
    expect(p.latitude).toBeCloseTo(at(500).latitude, 5);
    expect(pointAtDistance(L, -5)).toEqual(L.coords[0]);
    expect(pointAtDistance(L, 99_999)).toEqual(L.coords[L.coords.length - 1]);
  });
});

describe("projectOnTrack", () => {
  it("places a position on the trail", () => {
    const p = projectOnTrack(L, at(500, 0));
    expect(p.alongM).toBeCloseTo(500, 0);
    expect(p.offTrackM).toBeLessThan(0.5);
  });
  it("measures the distance off the trail", () => {
    const p = projectOnTrack(L, at(500, 80));
    expect(p.offTrackM).toBeCloseTo(80, 0);
    expect(p.alongM).toBeCloseTo(500, 0);
  });
  it("clamps beyond the ends", () => {
    expect(projectOnTrack(L, at(-50, 0)).alongM).toBe(0);
    expect(projectOnTrack(L, at(1000, 1500)).alongM).toBeCloseTo(L.totalM, 0);
  });
  it("handles a one-point trail", () => {
    const one = buildTrackIndex([at(0)]);
    expect(projectOnTrack(one, at(0, 40)).offTrackM).toBeCloseTo(40, 0);
  });
  it("stays abeam of the position far from the trail, whatever the previous progress", () => {
    // Regression: neighbouring segments used to count as separate "passes" far off the trail.
    const p = projectOnTrack(L, at(500, -120), 0);
    expect(p.alongM).toBeCloseTo(500, 0);
    expect(p.offTrackM).toBeCloseTo(120, 0);
  });
  it("uses the previous progress to pick the right pass of an out-and-back", () => {
    expect(projectOnTrack(OAB, at(300, 0), 300).alongM).toBeCloseTo(300, 0);
    expect(projectOnTrack(OAB, at(300, 0), 1700).alongM).toBeCloseTo(1700, 0);
    expect(projectOnTrack(OAB, at(300, 60), 1700).alongM).toBeCloseTo(1700, 0);
  });
  it("without a hint takes the closest point", () => {
    const p = projectOnTrack(L, at(900, 30));
    expect(p.alongM).toBeCloseTo(900, 0);
  });
});

describe("nextTurn", () => {
  it("finds a right turn ahead", () => {
    const turn = nextTurn(L, 800);
    expect(turn).toMatchObject({ direction: "right", sharp: false });
    expect(turn!.inM).toBeGreaterThanOrEqual(150);
    expect(turn!.inM).toBeLessThanOrEqual(260);
  });
  it("finds a left turn", () => {
    const left = buildTrackIndex(line([0, 0], [1000, 0], [1000, -1000]));
    expect(nextTurn(left, 800)?.direction).toBe("left");
  });
  it("calls a hairpin sharp", () => {
    expect(nextTurn(OAB, 800)).toMatchObject({ sharp: true });
  });
  it("sees nothing on a straight stretch or beyond the look-ahead", () => {
    expect(nextTurn(L, 100)).toBeNull();
    expect(nextTurn(L, 500, 100)).toBeNull();
  });
  it("sees nothing near the end", () => {
    expect(nextTurn(L, L.totalM - 20)).toBeNull();
  });
});

describe("trackUpTo", () => {
  it("returns the covered part, ending at the given distance", () => {
    const done = trackUpTo(L, 505);
    expect(done[0]).toEqual(L.coords[0]);
    expect(done[done.length - 1].latitude).toBeCloseTo(at(505).latitude, 5);
    expect(trackUpTo(L, 0)).toEqual([]);
  });
});

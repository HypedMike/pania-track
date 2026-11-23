import { describe, expect, it } from "vitest";
import { interpolateByIndex, sampleIndices } from "./terrain";

describe("sampleIndices", () => {
  it("takes every index when there are few", () => {
    expect(sampleIndices(3, 10)).toEqual([0, 1, 2]);
    expect(sampleIndices(0, 10)).toEqual([]);
  });

  it("spreads a limited number evenly, keeping both ends", () => {
    const idx = sampleIndices(1001, 11);
    expect(idx).toHaveLength(11);
    expect(idx[0]).toBe(0);
    expect(idx[10]).toBe(1000);
    expect(idx[5]).toBe(500);
  });
});

describe("interpolateByIndex", () => {
  it("fills in between the known values with straight lines", () => {
    expect(interpolateByIndex([0, 4], [100, 200], 5)).toEqual([100, 125, 150, 175, 200]);
  });

  it("keeps the known values where they are", () => {
    const out = interpolateByIndex([0, 2, 4], [10, 30, 20], 5);
    expect(out[0]).toBe(10);
    expect(out[2]).toBe(30);
    expect(out[4]).toBe(20);
    expect(out[3]).toBe(25);
  });

  it("holds the first and last value outside the known range", () => {
    expect(interpolateByIndex([1, 3], [5, 7], 5)).toEqual([5, 5, 6, 7, 7]);
  });
});

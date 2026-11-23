import { describe, expect, it } from "vitest";
import type { PaceProfile } from "../../shared/analysis/analysis_api";
import { paceFactor, profileSpeedMs, secondsAt } from "./pace_eta";

/** 4 km: the first kilometer takes 1000 s, the second 2000 s (a climb), the last two 1000 s each. */
const PROFILE: PaceProfile = { stepM: 1000, totalM: 4000, seconds: [0, 1000, 3000, 4000, 5000] };

describe("secondsAt", () => {
  it("reads the profile at its steps and between them", () => {
    expect(secondsAt(PROFILE, 0)).toBe(0);
    expect(secondsAt(PROFILE, 1000)).toBe(1000);
    expect(secondsAt(PROFILE, 1500)).toBe(2000);
    expect(secondsAt(PROFILE, 4000)).toBe(5000);
  });

  it("stays inside the trail", () => {
    expect(secondsAt(PROFILE, -50)).toBe(0);
    expect(secondsAt(PROFILE, 99_999)).toBe(5000);
  });

  it("handles a last step shorter than the others", () => {
    const p: PaceProfile = { stepM: 1000, totalM: 1500, seconds: [0, 1000, 1500] };
    expect(secondsAt(p, 1250)).toBe(1250);
    expect(secondsAt({ stepM: 50, totalM: 0, seconds: [] }, 10)).toBe(0);
  });
});

describe("paceFactor", () => {
  it("is 1 until there is enough to compare", () => {
    expect(paceFactor(PROFILE, 0, 50, 60)).toBe(1);
    expect(paceFactor(PROFILE, 0, 1000, 60)).toBe(1);
  });

  it("is the ratio of the time taken to the time predicted", () => {
    expect(paceFactor(PROFILE, 0, 1000, 1000)).toBeCloseTo(1);
    expect(paceFactor(PROFILE, 0, 1000, 1200)).toBeCloseTo(1.2);
    expect(paceFactor(PROFILE, 0, 3000, 3000)).toBeCloseTo(0.75);
  });

  it("is kept within reason", () => {
    expect(paceFactor(PROFILE, 0, 1000, 100_000)).toBe(1.8);
    expect(paceFactor(PROFILE, 0, 1000, 200)).toBe(0.6);
  });

  it("measures from where the person joined the trail", () => {
    // Joined at 1000 m and took 2400 s for the 2000 s the model gives for the next kilometer.
    expect(paceFactor(PROFILE, 1000, 2000, 2400)).toBeCloseTo(1.2);
  });
});

describe("profileSpeedMs", () => {
  it("gives the model's own speed for what is left when the person is on the model", () => {
    // 3 km left, the model expects 4000 s: 0.75 m/s.
    expect(profileSpeedMs(PROFILE, 1000, 0, 1000)).toBeCloseTo(0.75);
  });

  it("slows the rest of the trail down when the person is behind the model", () => {
    const onModel = profileSpeedMs(PROFILE, 1000, 0, 1000)!;
    const slow = profileSpeedMs(PROFILE, 1000, 0, 1500)!;
    expect(slow).toBeCloseTo(onModel / 1.5);
  });

  it("knows a climb is coming: the same remaining distance takes longer", () => {
    // 3 km left before the climb, 2 km left after it, same pace but different terrain.
    expect(profileSpeedMs(PROFILE, 0, 0, 0)!).toBeLessThan(profileSpeedMs(PROFILE, 3000, 0, 0)!);
  });

  it("has no speed at the end of the trail", () => {
    expect(profileSpeedMs(PROFILE, 4000, 0, 5000)).toBeNull();
    expect(profileSpeedMs({ stepM: 50, totalM: 0, seconds: [0] }, 0, 0, 0)).toBeNull();
  });
});

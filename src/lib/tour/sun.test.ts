import { describe, expect, it } from "vitest";
import { isDark, nextSunset, sunEvents } from "./sun";

const minutesUtc = (ms: number) => {
  const d = new Date(ms);
  return d.getUTCHours() * 60 + d.getUTCMinutes();
};

// Reference times come from an independent NOAA solar calculation.
describe("sun", () => {
  it("sunset in the Alps at midsummer", () => {
    const s = nextSunset(46, 11, Date.UTC(2026, 5, 21, 12))!;
    expect(Math.abs(minutesUtc(s) - (19 * 60 + 9))).toBeLessThanOrEqual(8);
  });
  it("sunset in the Alps in late November", () => {
    const s = nextSunset(46, 11, Date.UTC(2026, 10, 23, 12))!;
    expect(Math.abs(minutesUtc(s) - (15 * 60 + 38))).toBeLessThanOrEqual(8);
  });
  it("western longitudes land on the right day", () => {
    const s = nextSunset(40.7, -74, Date.UTC(2026, 5, 21, 16))!;
    const d = new Date(s);
    expect(d.getUTCDate()).toBe(22);
    expect(Math.abs(minutesUtc(s) - 30)).toBeLessThanOrEqual(10);
  });
  it("tells day from night", () => {
    expect(isDark(46, 11, Date.UTC(2026, 10, 23, 11))).toBe(false);
    expect(isDark(46, 11, Date.UTC(2026, 10, 23, 18))).toBe(true);
    expect(isDark(46, 11, Date.UTC(2026, 10, 23, 3))).toBe(true);
  });
  it("alternates sunrises and sunsets in order", () => {
    const events = sunEvents(46, 11, Date.UTC(2026, 10, 23, 12));
    for (let i = 1; i < events.length; i++) {
      expect(events[i].time).toBeGreaterThan(events[i - 1].time);
      expect(events[i].type).not.toBe(events[i - 1].type);
    }
  });
  it("has no sunset in polar day, and counts it as light", () => {
    const june = Date.UTC(2026, 5, 21, 12);
    expect(nextSunset(80, 0, june)).toBeNull();
    expect(isDark(80, 0, june)).toBe(false);
  });
});

import { describe, expect, it } from "vitest";
import { OffTrackMonitor } from "./off_track_monitor";

const T = 50;

describe("OffTrackMonitor", () => {
  it("ignores a single stray fix", () => {
    const m = new OffTrackMonitor();
    expect(m.onFix(80, 5, T, 0)).toBeNull();
    expect(m.offTrack).toBe(false);
  });
  it("alerts on two fixes in a row", () => {
    const m = new OffTrackMonitor();
    m.onFix(80, 5, T, 0);
    expect(m.onFix(90, 5, T, 3000)).toBe("alert");
    expect(m.offTrack).toBe(true);
  });
  it("a fix back on the trail resets the count", () => {
    const m = new OffTrackMonitor();
    m.onFix(80, 5, T, 0);
    m.onFix(10, 5, T, 3000);
    expect(m.onFix(80, 5, T, 6000)).toBeNull();
  });
  it("does not count fixes less accurate than the threshold", () => {
    const m = new OffTrackMonitor();
    m.onFix(80, 5, T, 0);
    expect(m.onFix(90, 200, T, 3000)).toBeNull();
    expect(m.onFix(90, 5, T, 6000)).toBe("alert");
  });
  it("reminds every two minutes while still off", () => {
    const m = new OffTrackMonitor();
    m.onFix(80, 5, T, 0);
    m.onFix(80, 5, T, 1000);
    expect(m.onFix(80, 5, T, 60_000)).toBeNull();
    expect(m.onFix(80, 5, T, 121_000)).toBe("remind");
    expect(m.onFix(80, 5, T, 130_000)).toBeNull();
  });
  it("clears only once well within the threshold", () => {
    const m = new OffTrackMonitor();
    m.onFix(80, 5, T, 0);
    m.onFix(80, 5, T, 1000);
    expect(m.onFix(45, 5, T, 2000)).toBeNull(); // inside 50 but not inside 70% of it
    expect(m.offTrack).toBe(true);
    expect(m.onFix(30, 5, T, 3000)).toBe("back");
    expect(m.offTrack).toBe(false);
  });
  it("can alert again after coming back", () => {
    const m = new OffTrackMonitor();
    m.onFix(80, 5, T, 0);
    m.onFix(80, 5, T, 1000);
    m.onFix(10, 5, T, 2000);
    m.onFix(80, 5, T, 3000);
    expect(m.onFix(80, 5, T, 4000)).toBe("alert");
  });
  it("reset clears everything", () => {
    const m = new OffTrackMonitor();
    m.onFix(80, 5, T, 0);
    m.onFix(80, 5, T, 1000);
    m.reset();
    expect(m.offTrack).toBe(false);
    expect(m.onFix(80, 5, T, 2000)).toBeNull();
  });
});

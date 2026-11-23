import { describe, expect, it } from "vitest";
import { summarizeWalkWeather } from "./history";

const HOURLY = {
  time: ["2024-06-01T06:00", "2024-06-01T07:00", "2024-06-01T08:00", "2024-06-01T09:00"],
  temperature_2m: [10, 14, 18, 22],
  precipitation: [0, 1.5, 0.5, 0],
};
const at = (h: number, m = 0) => Date.parse(`2024-06-01T${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:00Z`);

describe("summarizeWalkWeather", () => {
  it("averages the temperature and adds up the rain over the hours of the walk", () => {
    // 07:15 to 08:45 touches the 07:00 and 08:00 hours.
    const w = summarizeWalkWeather(HOURLY, at(7, 15), at(8, 45))!;
    expect(w.tempC).toBe(16);
    expect(w.precipMm).toBe(2);
  });

  it("includes the hour a walk ends in and excludes hours before it began", () => {
    const w = summarizeWalkWeather(HOURLY, at(8, 30), at(9, 0))!;
    expect(w.tempC).toBe(20);
  });

  it("is null when the walk has no data around it", () => {
    expect(summarizeWalkWeather(HOURLY, at(12), at(13))).toBeNull();
    expect(summarizeWalkWeather({ ...HOURLY, temperature_2m: [null, null, null, null] }, at(6), at(9))).toBeNull();
  });

  it("treats missing rain as none", () => {
    const w = summarizeWalkWeather({ ...HOURLY, precipitation: [null, null, null, null] }, at(6), at(9))!;
    expect(w.precipMm).toBe(0);
  });
});

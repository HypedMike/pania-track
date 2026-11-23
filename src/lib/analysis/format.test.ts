import { describe, expect, it } from "vitest";
import { formatDelta, formatGrade, formatSeconds, formatSpeed, formatVerticalSpeed } from "./format";

describe("formatSpeed", () => {
  it("converts m/s to km/h", () => {
    expect(formatSpeed(1)).toBe("3.6 km/h");
    expect(formatSpeed(null)).toBe("—");
    expect(formatSpeed(undefined)).toBe("—");
  });
});

describe("formatSeconds", () => {
  it("shows minutes, and hours when there are some", () => {
    expect(formatSeconds(0)).toBe("0m");
    expect(formatSeconds(125)).toBe("2m");
    expect(formatSeconds(3_900)).toBe("1h 05m");
    expect(formatSeconds(null)).toBe("—");
  });

  it("ignores the sign", () => {
    expect(formatSeconds(-600)).toBe("10m");
  });
});

describe("formatDelta", () => {
  it("is signed, and calls almost nothing zero", () => {
    expect(formatDelta(600)).toBe("+10m");
    expect(formatDelta(-4_000)).toBe("−1h 07m");
    expect(formatDelta(20)).toBe("±0m");
    expect(formatDelta(-20)).toBe("±0m");
  });
});

describe("formatGrade", () => {
  it("is signed and rounded", () => {
    expect(formatGrade(12.4)).toBe("+12%");
    expect(formatGrade(-5.6)).toBe("−6%");
    expect(formatGrade(0.2)).toBe("0%");
  });
});

describe("formatVerticalSpeed", () => {
  it("is meters per hour", () => {
    expect(formatVerticalSpeed(623.4)).toBe("623 m/h");
    expect(formatVerticalSpeed(null)).toBe("—");
  });
});

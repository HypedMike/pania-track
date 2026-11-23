import { currentLocale, type TFunction } from "../i18n/i18n";

/** Progress of the update download, as reported by the Rust backend. */
export interface DownloadProgress {
  downloaded: number;
  /** Null when the server did not say how big the file is. */
  total: number | null;
  /** Smoothed current speed, bytes per second. */
  speedBps: number;
  /** Seconds left at the current speed, or null when it cannot be estimated. */
  etaSeconds: number | null;
  done: boolean;
}

const UNITS = ["B", "KB", "MB", "GB"];

export function formatBytes(bytes: number): string {
  let value = Math.max(0, bytes);
  let unit = 0;
  while (value >= 1024 && unit < UNITS.length - 1) {
    value /= 1024;
    unit++;
  }
  const digits = unit === 0 ? 0 : value < 10 ? 2 : 1;
  return `${value.toLocaleString(currentLocale(), { minimumFractionDigits: digits, maximumFractionDigits: digits })} ${UNITS[unit]}`;
}

export function formatSpeed(bytesPerSecond: number): string {
  return `${formatBytes(bytesPerSecond)}/s`;
}

/** "8 s" or "2 min 5 s". */
export function formatEta(seconds: number, t: TFunction): string {
  const s = Math.max(0, Math.round(seconds));
  return s < 60 ? t("update.etaSeconds", { n: s }) : t("update.etaMinutes", { m: Math.floor(s / 60), s: s % 60 });
}

/** 0–100, or null when the total size is unknown. */
export function percent(p: DownloadProgress): number | null {
  if (p.total === null || p.total <= 0) return null;
  return Math.min(100, Math.floor((p.downloaded / p.total) * 100));
}

/** The line under the bar: "12.3 MB of 31.0 MB · 2.4 MB/s · about 8 s left". */
export function describeProgress(p: DownloadProgress, t: TFunction): string {
  const parts = [
    p.total !== null
      ? t("update.progressKnown", { done: formatBytes(p.downloaded), total: formatBytes(p.total) })
      : t("update.progressUnknown", { done: formatBytes(p.downloaded) }),
  ];
  if (p.speedBps > 1) parts.push(formatSpeed(p.speedBps));
  if (p.etaSeconds !== null && p.etaSeconds > 0 && !p.done) parts.push(t("update.eta", { time: formatEta(p.etaSeconds, t) }));
  return parts.join(" · ");
}

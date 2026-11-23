import { currentLocale, t, type TFunction } from "../../shared/i18n/i18n";
import { formatDuration } from "../../shared/gps/trail_stats";
import type { TourWarning } from "./tour_guidance";

/** Clock time such as "14:35", in the app's language. */
export function formatTimeOfDay(ms: number): string {
  return new Date(ms).toLocaleTimeString(currentLocale(), { hour: "2-digit", minute: "2-digit" });
}

/** Speed in km/h with one decimal. */
export function formatSpeed(ms: number): string {
  return `${(ms * 3.6).toFixed(1)} km/h`;
}

/** The sentence that explains a warning. */
export function warningText(w: TourWarning, translate: TFunction = t): string {
  const d = w.data;
  switch (w.kind) {
    case "offTrack":
      return translate("tour.warn.offTrack", { m: d.m });
    case "noGps":
      return translate("tour.warn.noGps", { time: formatTimeOfDay(d.sinceMs) });
    case "late": {
      const params = {
        eta: formatTimeOfDay(d.etaMs),
        target: formatTimeOfDay(d.targetMs),
        late: formatDuration(d.lateByMs),
        speed: formatSpeed(d.neededSpeedMs),
      };
      // When the wanted time has already passed there is no pace that would still make it.
      return translate(d.neededSpeedMs > 0 ? "tour.warn.late" : "tour.warn.latePassed", params);
    }
    case "afterDark":
      return translate("tour.warn.afterDark", { eta: formatTimeOfDay(d.etaMs), sunset: formatTimeOfDay(d.sunsetMs) });
    case "dark":
      return translate("tour.warn.dark");
    case "storm":
    case "snow":
      return translate(`tour.warn.${w.kind}`, { time: formatTimeOfDay(d.atMs) });
    case "rain":
      return translate("tour.warn.rain", { time: formatTimeOfDay(d.atMs), mm: d.mm });
    case "wind":
      return translate("tour.warn.wind", { time: formatTimeOfDay(d.atMs), kmh: d.kmh });
    case "heat":
    case "cold":
      return translate(`tour.warn.${w.kind}`, { time: formatTimeOfDay(d.atMs), c: d.c });
  }
}

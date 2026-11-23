import type { PaceProfile } from "../../shared/analysis/analysis_api";

/**
 * Arrival time from the person's own pace model. The model (see `analysis/pace.rs`) says how long
 * each stretch of the trail should take, given its slopes; during the tour that is scaled by how
 * the person is doing against it, so a slow day moves every later stretch too.
 */

/** Not enough tour behind us to say how the person compares to the model. */
const MIN_COMPARISON_S = 120;
/** A day is not more than this much faster or slower than the model says. */
const MIN_FACTOR = 0.6;
const MAX_FACTOR = 1.8;

/** Predicted seconds from the start of the trail to `alongM`. */
export function secondsAt(profile: PaceProfile, alongM: number): number {
  if (profile.seconds.length === 0) return 0;
  const along = Math.min(Math.max(alongM, 0), profile.totalM);
  const pos = along / profile.stepM;
  const lo = Math.min(Math.floor(pos), profile.seconds.length - 1);
  const hi = Math.min(lo + 1, profile.seconds.length - 1);
  if (hi === lo) return profile.seconds[lo];
  const loM = lo * profile.stepM;
  const hiM = Math.min(hi * profile.stepM, profile.totalM);
  const f = hiM > loM ? (along - loM) / (hiM - loM) : 0;
  return profile.seconds[lo] + (profile.seconds[hi] - profile.seconds[lo]) * f;
}

/**
 * How the person is doing against the model so far: 1 is on the model, 1.2 is 20% slower. 1 until
 * there are a couple of minutes to judge by.
 */
export function paceFactor(profile: PaceProfile, startAlongM: number, alongM: number, elapsedS: number): number {
  const predicted = secondsAt(profile, alongM) - secondsAt(profile, startAlongM);
  if (predicted < MIN_COMPARISON_S || elapsedS < MIN_COMPARISON_S) return 1;
  return Math.min(MAX_FACTOR, Math.max(MIN_FACTOR, elapsedS / predicted));
}

/**
 * The speed (m/s) that gets the person from `alongM` to the end of the trail in the time the
 * model expects, adjusted by how they are doing. `null` at the end of the trail.
 */
export function profileSpeedMs(
  profile: PaceProfile,
  alongM: number,
  startAlongM: number,
  elapsedS: number,
): number | null {
  const remainingM = profile.totalM - alongM;
  const predictedRemaining = secondsAt(profile, profile.totalM) - secondsAt(profile, alongM);
  if (remainingM <= 0 || predictedRemaining <= 0) return null;
  return remainingM / (predictedRemaining * paceFactor(profile, startAlongM, alongM, elapsedS));
}

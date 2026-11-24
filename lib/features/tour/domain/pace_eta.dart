import 'dart:math' as math;

import '../../../core/rust/analysis/pace.dart' show Profile;

/// Arrival time from the person's own pace model. The model (see `rust/src/analysis/pace.rs`)
/// says how long each stretch of the trail should take, given its slopes; during the tour that is
/// scaled by how the person is doing against it, so a slow day moves every later stretch too.

/// Not enough tour behind us to say how the person compares to the model.
const double _minComparisonS = 120;

/// A day is not more than this much faster or slower than the model says.
const double _minFactor = 0.6;
const double _maxFactor = 1.8;

/// Predicted seconds from the start of the trail to [alongM].
double secondsAt(Profile profile, double alongM) {
  final seconds = profile.seconds;
  if (seconds.isEmpty) return 0;
  final along = math.min(math.max(alongM, 0), profile.totalM);
  final pos = along / profile.stepM;
  final lo = math.min(pos.floor(), seconds.length - 1);
  final hi = math.min(lo + 1, seconds.length - 1);
  if (hi == lo) return seconds[lo];
  final loM = lo * profile.stepM;
  final hiM = math.min(hi * profile.stepM, profile.totalM);
  final f = hiM > loM ? (along - loM) / (hiM - loM) : 0.0;
  return seconds[lo] + (seconds[hi] - seconds[lo]) * f;
}

/// How the person is doing against the model so far: 1 is on the model, 1.2 is 20% slower. 1 until
/// there are a couple of minutes to judge by.
double paceFactor(Profile profile, double startAlongM, double alongM, double elapsedS) {
  final predicted = secondsAt(profile, alongM) - secondsAt(profile, startAlongM);
  if (predicted < _minComparisonS || elapsedS < _minComparisonS) return 1;
  return math.min(_maxFactor, math.max(_minFactor, elapsedS / predicted));
}

/// The speed (m/s) that gets the person from [alongM] to the end of the trail in the time the
/// model expects, adjusted by how they are doing. `null` at the end of the trail.
double? profileSpeedMs(Profile profile, double alongM, double startAlongM, double elapsedS) {
  final remainingM = profile.totalM - alongM;
  final predictedRemaining = secondsAt(profile, profile.totalM) - secondsAt(profile, alongM);
  if (remainingM <= 0 || predictedRemaining <= 0) return null;
  return remainingM / (predictedRemaining * paceFactor(profile, startAlongM, alongM, elapsedS));
}

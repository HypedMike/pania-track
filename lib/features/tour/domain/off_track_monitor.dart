enum OffTrackVerdict { alert, remind, back }

/// While still off the trail, remind every two minutes.
const int _repeatMs = 120000;

/// Once alerted, the person must come back within this share of the threshold to be cleared.
const double _clearShare = 0.7;

/// Decides when a stray from the trail is worth an alert. The same rules run natively in
/// `OffTrackGuard.kt` while the screen is off, so keep the two in step:
/// a single stray fix does not count (two in a row do), a fix less accurate than the threshold
/// says nothing, and coming back is only noticed once well within the threshold.
class OffTrackMonitor {
  int _consecutiveOff = 0;
  bool _alerted = false;
  int _lastAlertAt = 0;

  /// Whether an alert is currently raised.
  bool get offTrack => _alerted;

  void reset() {
    _consecutiveOff = 0;
    _alerted = false;
    _lastAlertAt = 0;
  }

  OffTrackVerdict? onFix(double offTrackM, double? accuracyM, double thresholdM, int nowMs) {
    if (accuracyM != null && accuracyM > thresholdM) return null;

    if (offTrackM > thresholdM) {
      _consecutiveOff++;
      if (_consecutiveOff < 2) return null;
      if (!_alerted) {
        _alerted = true;
        _lastAlertAt = nowMs;
        return OffTrackVerdict.alert;
      }
      if (nowMs - _lastAlertAt >= _repeatMs) {
        _lastAlertAt = nowMs;
        return OffTrackVerdict.remind;
      }
    } else if (offTrackM < thresholdM * _clearShare) {
      _consecutiveOff = 0;
      if (_alerted) {
        _alerted = false;
        return OffTrackVerdict.back;
      }
    }
    return null;
  }
}

import 'package:intl/intl.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/rust/updater/progress.dart';

const _units = ['B', 'KB', 'MB', 'GB'];

String formatBytes(num bytes) {
  var value = bytes < 0 ? 0.0 : bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < _units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 ? 0 : (value < 10 ? 2 : 1);
  final fmt = NumberFormat.decimalPatternDigits(locale: I18n.locale, decimalDigits: digits);
  return '${fmt.format(value)} ${_units[unit]}';
}

String formatSpeed(double bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

/// "8 s" or "2 min 5 s".
String formatEta(int seconds, TFunction t) {
  final s = seconds < 0 ? 0 : seconds;
  return s < 60 ? t('update.etaSeconds', {'n': s}) : t('update.etaMinutes', {'m': s ~/ 60, 's': s % 60});
}

/// 0–100, or null when the total size is unknown.
int? percent(Progress p) {
  final total = p.total;
  if (total == null || total <= BigInt.zero) return null;
  final pct = (p.downloaded.toDouble() / total.toDouble() * 100).floor();
  return pct > 100 ? 100 : pct;
}

/// The line under the bar: "12.3 MB of 31.0 MB · 2.4 MB/s · about 8 s left".
String describeProgress(Progress p, TFunction t) {
  final parts = <String>[
    p.total != null
        ? t('update.progressKnown', {'done': formatBytes(p.downloaded.toInt()), 'total': formatBytes(p.total!.toInt())})
        : t('update.progressUnknown', {'done': formatBytes(p.downloaded.toInt())}),
  ];
  if (p.speedBps > 1) parts.add(formatSpeed(p.speedBps));
  final eta = p.etaSeconds;
  if (eta != null && eta > BigInt.zero && !p.done) parts.add(t('update.eta', {'time': formatEta(eta.toInt(), t)}));
  return parts.join(' · ');
}

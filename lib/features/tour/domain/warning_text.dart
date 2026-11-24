import 'package:intl/intl.dart';

import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import 'tour_guidance.dart';

/// Clock time such as "14:35", in the app's language.
String formatTimeOfDay(int ms) => DateFormat.Hm(I18n.locale).format(DateTime.fromMillisecondsSinceEpoch(ms));

/// Speed in km/h with one decimal.
String formatSpeed(double ms) => '${(ms * 3.6).toStringAsFixed(1)} km/h';

/// The sentence that explains a warning.
String warningText(TourWarning w, [TFunction? translate]) {
  final t = translate ?? I18n.t;
  final d = w.data;
  switch (w.kind) {
    case WarningKind.offTrack:
      return t('tour.warn.offTrack', {'m': d['m']});
    case WarningKind.noGps:
      return t('tour.warn.noGps', {'time': formatTimeOfDay(d['sinceMs']!.toInt())});
    case WarningKind.late:
      final params = {
        'eta': formatTimeOfDay(d['etaMs']!.toInt()),
        'target': formatTimeOfDay(d['targetMs']!.toInt()),
        'late': formatDuration(d['lateByMs']!.toInt()),
        'speed': formatSpeed(d['neededSpeedMs']!.toDouble()),
      };
      // When the wanted time has already passed there is no pace that would still make it.
      return t(d['neededSpeedMs']! > 0 ? 'tour.warn.late' : 'tour.warn.latePassed', params);
    case WarningKind.afterDark:
      return t('tour.warn.afterDark', {
        'eta': formatTimeOfDay(d['etaMs']!.toInt()),
        'sunset': formatTimeOfDay(d['sunsetMs']!.toInt()),
      });
    case WarningKind.dark:
      return t('tour.warn.dark');
    case WarningKind.storm:
    case WarningKind.snow:
      return t('tour.warn.${w.kind.name}', {'time': formatTimeOfDay(d['atMs']!.toInt())});
    case WarningKind.rain:
      return t('tour.warn.rain', {'time': formatTimeOfDay(d['atMs']!.toInt()), 'mm': d['mm']});
    case WarningKind.wind:
      return t('tour.warn.wind', {'time': formatTimeOfDay(d['atMs']!.toInt()), 'kmh': d['kmh']});
    case WarningKind.heat:
    case WarningKind.cold:
      return t('tour.warn.${w.kind.name}', {'time': formatTimeOfDay(d['atMs']!.toInt()), 'c': d['c']});
  }
}

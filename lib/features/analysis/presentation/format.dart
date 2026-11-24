import 'package:intl/intl.dart';

import '../../../core/i18n/i18n.dart';

/// m/s as "4.3 km/h".
String formatSpeedKmh(double? ms) => ms == null ? '—' : '${(ms * 3.6).toStringAsFixed(1)} km/h';

/// Seconds as "1h 05m" or "12m" (see `formatDuration`, which takes milliseconds).
String formatSeconds(double? seconds) {
  if (seconds == null) return '—';
  final total = (seconds.abs() / 60).round();
  final h = total ~/ 60;
  final m = total % 60;
  return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
}

/// A difference in time with its sign: "+12m" is slower than planned, "−3m" is faster.
String formatDelta(double seconds) {
  if (seconds.abs() < 30) return '±0m';
  return '${seconds > 0 ? '+' : '−'}${formatSeconds(seconds)}';
}

/// Percent slope as "+12%" or "−5%".
String formatGrade(double pct) {
  final rounded = pct.round();
  return '${rounded > 0
      ? '+'
      : rounded < 0
      ? '−'
      : ''}${rounded.abs()}%';
}

/// Clock time of a point in time, in the app's language.
String formatClockTime(int ms) => DateFormat.Hm(I18n.locale).format(DateTime.fromMillisecondsSinceEpoch(ms));

/// Meters per hour of climbing, "620 m/h".
String formatVerticalSpeed(double? mh) => mh == null ? '—' : '${mh.round()} m/h';

/// Month names in the app's language, January first.
List<String> monthNames() => List.generate(12, (i) => DateFormat.MMM(I18n.locale).format(DateTime(2024, i + 1, 1)));

/// Weekday names in the app's language, Monday first.
List<String> weekdayNames() => List.generate(7, (i) => DateFormat.E(I18n.locale).format(DateTime(2024, 1, 1 + i)));

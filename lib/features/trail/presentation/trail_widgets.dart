import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/rust/analysis/geo.dart';
import '../../../core/ui/widgets.dart';
import '../domain/gps_coordinate.dart';
import '../domain/trail.dart';

const List<Activity> activities = [Activity.foot, Activity.bike];

/// Segmented control to choose whether a trail is done on foot or by bike.
class ActivityPicker extends StatelessWidget {
  const ActivityPicker({super.key, required this.value, required this.onChanged, required this.t});

  final Activity value;
  final ValueChanged<Activity> onChanged;
  final TFunction t;

  @override
  Widget build(BuildContext context) => SegmentedChoice<Activity>(
    label: t('activity.label'),
    options: [for (final a in activities) (a, t('activity.${a.name}'))],
    value: value,
    onChanged: onChanged,
  );
}

/// Where a trail came from.
class SourceBadge extends StatelessWidget {
  const SourceBadge(this.source, {super.key, required this.t});

  final TrailSource source;
  final TFunction t;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (source) {
      TrailSource.recorded => (c.brandTint, c.brandTintInk),
      TrailSource.imported => (c.routeTint, c.routeInk),
      TrailSource.planned => (c.line, c.inkSoft),
      TrailSource.bookmarked => (c.warnTint, c.warnInk),
    };
    final label = switch (source) {
      TrailSource.recorded => 'trail.sourceRecorded',
      TrailSource.imported => 'trail.sourceImported',
      TrailSource.planned => 'trail.sourcePlanned',
      TrailSource.bookmarked => 'trail.sourceBookmarked',
    };
    return Pill(t(label), background: bg, foreground: fg);
  }
}

/// Small schematic of a trail's shape, used as a list thumbnail.
class TrailPreview extends StatelessWidget {
  const TrailPreview({super.key, required this.coordinates, required this.source, this.size = 72});

  final List<GpsCoordinate> coordinates;
  final TrailSource source;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.map, borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: coordinates.length < 2
          ? null
          : CustomPaint(
              painter: _PreviewPainter(
                coordinates,
                source == TrailSource.imported ? c.route : c.brandFg,
                c.surface,
                c.ink,
              ),
            ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.coordinates, this.line, this.fill, this.stroke);

  final List<GpsCoordinate> coordinates;
  final Color line;
  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 10.0;
    final lats = coordinates.map((c) => c.latitude);
    final lons = coordinates.map((c) => c.longitude);
    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final minLon = lons.reduce(math.min);
    final maxLon = lons.reduce(math.max);
    // Longitude degrees shrink with latitude; correct so the shape isn't stretched.
    final lonScale = math.cos(((minLat + maxLat) / 2) * math.pi / 180);
    final w = (maxLon - minLon) * lonScale == 0 ? 1e-9 : (maxLon - minLon) * lonScale;
    final h = maxLat - minLat == 0 ? 1e-9 : maxLat - minLat;
    final scale = (size.width - pad * 2) / math.max(w, h);
    final offX = (size.width - w * scale) / 2;
    final offY = (size.height - h * scale) / 2;
    Offset at(GpsCoordinate c) =>
        Offset(offX + (c.longitude - minLon) * lonScale * scale, size.height - (offY + (c.latitude - minLat) * scale));

    final path = Path()..moveTo(at(coordinates.first).dx, at(coordinates.first).dy);
    for (final c in coordinates.skip(1)) {
      final p = at(c);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final start = at(coordinates.first);
    canvas.drawCircle(start, 4, Paint()..color = fill);
    canvas.drawCircle(
      start,
      4,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.coordinates != coordinates || old.line != line;
}

/// Elevation along a trail.
class ElevationProfile extends StatelessWidget {
  const ElevationProfile({super.key, required this.coordinates, required this.t});

  final List<GpsCoordinate> coordinates;
  final TFunction t;

  @override
  Widget build(BuildContext context) {
    final alts = [
      for (final c in coordinates)
        if (c.altitude != null) c.altitude!,
    ];
    if (alts.length < 2) return const SizedBox.shrink();
    final c = context.colors;
    final min = alts.reduce(math.min);
    final max = alts.reduce(math.max);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(t('elevation.title'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text('${min.round()} – ${max.round()} m', style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            label: t('elevation.alt', {'min': min.round(), 'max': max.round()}),
            child: SizedBox(
              height: 96,
              child: CustomPaint(painter: _ElevationPainter(alts, min, max, c.route), size: Size.infinite),
            ),
          ),
        ],
      ),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  _ElevationPainter(this.alts, this.min, this.max, this.color);

  final List<double> alts;
  final double min;
  final double max;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final range = max - min == 0 ? 1.0 : max - min;
    final line = Path();
    for (var i = 0; i < alts.length; i++) {
      final x = i / (alts.length - 1) * size.width;
      final y = size.height - 8 - (alts[i] - min) / range * (size.height - 16);
      i == 0 ? line.moveTo(x, y) : line.lineTo(x, y);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.14));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ElevationPainter old) => old.alts != alts || old.color != color;
}

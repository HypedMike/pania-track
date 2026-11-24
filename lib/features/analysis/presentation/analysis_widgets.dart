import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../data/analysis_api.dart';

/// A titled block of the analysis pages.
class AnalysisCard extends StatelessWidget {
  const AnalysisCard({super.key, required this.title, required this.children, this.aside});

  final String title;
  final String? aside;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              if (aside != null)
                Flexible(
                  child: Text(
                    aside!,
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ),
            ],
          ),
          for (final child in children) ...[const SizedBox(height: 12), child],
        ],
      ),
    );
  }
}

/// A small labelled number.
class Figure extends StatelessWidget {
  const Figure({super.key, required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        if (hint != null) Text(hint!, style: TextStyle(fontSize: 12, color: c.muted)),
      ],
    );
  }
}

/// A row of equal-width figures.
class FigureRow extends StatelessWidget {
  const FigureRow(this.figures, {super.key});

  final List<Figure> figures;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [for (final f in figures) Expanded(child: f)],
  );
}

enum Tone { brand, route, muted, good, bad }

/// Plain vertical bars, one per value, with a label under some of them. Values may be negative
/// (bars then hang from a zero line). [tones] picks the colour of each bar.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.values,
    required this.semanticLabel,
    this.labels,
    this.labelEvery = 1,
    this.tones,
    this.highlight,
    this.height = 96,
  });

  final List<double> values;
  final List<String>? labels;
  final int labelEvery;
  final List<Tone>? tones;

  /// Index of a bar to draw in full colour while the others are dimmed.
  final int? highlight;
  final double height;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    Color fill(Tone tone) => switch (tone) {
      Tone.brand => c.brand,
      Tone.route => c.route,
      Tone.muted => c.lineStrong,
      Tone.good => c.brand,
      Tone.bad => c.danger,
    };
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _BarPainter(
            values: values,
            labels: labels,
            labelEvery: labelEvery,
            colors: [for (var i = 0; i < values.length; i++) fill(tones?[i] ?? Tone.brand)],
            highlight: highlight,
            line: c.line,
            labelColor: c.muted,
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.values,
    required this.labels,
    required this.labelEvery,
    required this.colors,
    required this.highlight,
    required this.line,
    required this.labelColor,
  });

  final List<double> values;
  final List<String>? labels;
  final int labelEvery;
  final List<Color> colors;
  final int? highlight;
  final Color line;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final labelH = labels != null ? 14.0 : 0.0;
    final plotH = size.height - labelH;
    final maxV = values.fold<double>(0, math.max);
    final minV = values.fold<double>(0, math.min);
    final range = maxV - minV == 0 ? 1.0 : maxV - minV;
    final zeroY = 4 + (maxV / range) * (plotH - 8);
    final slot = size.width / values.length;
    final barW = math.max(2.0, slot * 0.7);
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = line
        ..strokeWidth = 1,
    );
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final h = v.abs() / range * (plotH - 8);
      final y = v >= 0 ? zeroY - h : zeroY;
      final dimmed = highlight != null && highlight != i;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * slot + (slot - barW) / 2, y, barW, math.max(h, v == 0 ? 0 : 1)),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, Paint()..color = colors[i].withValues(alpha: dimmed ? 0.35 : 1));
    }
    final l = labels;
    if (l != null) {
      for (var i = 0; i < l.length; i += labelEvery) {
        final tp = TextPainter(
          text: TextSpan(
            text: l[i],
            style: TextStyle(fontSize: 9, color: labelColor),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(i * slot + slot / 2 - tp.width / 2, size.height - tp.height - 1));
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values || old.highlight != highlight || old.colors.length != colors.length;
}

/// Speed (km/h) at each slope; the person's own data in solid colour, estimates dimmed.
class PaceCurve extends StatelessWidget {
  const PaceCurve({super.key, required this.model, required this.semanticLabel});

  final PaceModel model;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => BarChart(
    values: [for (final b in model.bins) b.speedMs * 3.6],
    labels: [for (final b in model.bins) '${b.gradePct > 0 ? '+' : ''}${b.gradePct.round()}'],
    labelEvery: 2,
    tones: [for (final b in model.bins) b.measured ? Tone.brand : Tone.muted],
    height: 110,
    semanticLabel: semanticLabel,
  );
}

/// Altitude against distance, with climbs and descents shaded, stops marked and a replay cursor.
class ProfileChart extends StatelessWidget {
  const ProfileChart({
    super.key,
    required this.distances,
    required this.altitudes,
    required this.semanticLabel,
    this.segments = const [],
    this.stops = const [],
    this.cursor,
  });

  /// Meters from the start, one per point.
  final List<double> distances;

  /// Altitude of each point (meters), null where unknown.
  final List<double?> altitudes;
  final List<Segment> segments;
  final List<Stop> stops;

  /// Index of the point the replay is at.
  final int? cursor;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final known = <(double, double)>[
      for (var i = 0; i < distances.length; i++)
        if (altitudes[i] != null) (distances[i], altitudes[i]!),
    ];
    if (known.length < 2) return const SizedBox.shrink();
    final c = context.colors;
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: 110,
        width: double.infinity,
        child: CustomPaint(
          painter: _ProfilePainter(
            known: known,
            total: distances.last == 0 ? 1 : distances.last,
            segments: segments,
            stops: stops,
            cursorD: cursor == null ? null : distances[math.min(cursor!, distances.length - 1)],
            route: c.route,
            climb: c.grades[2],
            alt: c.alt,
            surface: c.surface,
            ink: c.ink,
            brand: c.brand,
          ),
        ),
      ),
    );
  }
}

class _ProfilePainter extends CustomPainter {
  _ProfilePainter({
    required this.known,
    required this.total,
    required this.segments,
    required this.stops,
    required this.cursorD,
    required this.route,
    required this.climb,
    required this.alt,
    required this.surface,
    required this.ink,
    required this.brand,
  });

  final List<(double, double)> known;
  final double total;
  final List<Segment> segments;
  final List<Stop> stops;
  final double? cursorD;
  final Color route, climb, alt, surface, ink, brand;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 8.0;
    const maxPoints = 400;
    final mn = known.map((k) => k.$2).reduce(math.min);
    final mx = known.map((k) => k.$2).reduce(math.max);
    final range = mx - mn == 0 ? 1.0 : mx - mn;
    double x(double d) => d / total * size.width;
    double y(double a) => size.height - pad - (a - mn) / range * (size.height - 2 * pad);

    for (final s in segments) {
      final color = switch (s.kind) {
        SegmentKind.climb => climb,
        SegmentKind.descent => route,
        SegmentKind.flat => null,
      };
      if (color == null) continue;
      canvas.drawRect(
        Rect.fromLTWH(x(s.startM), 0, math.max(1, x(s.endM) - x(s.startM)), size.height),
        Paint()..color = color.withValues(alpha: 0.16),
      );
    }

    final step = math.max(1, (known.length / maxPoints).ceil());
    final thinned = [
      for (var i = 0; i < known.length; i++)
        if (i % step == 0 || i == known.length - 1) known[i],
    ];
    final path = Path();
    for (var i = 0; i < thinned.length; i++) {
      final p = Offset(x(thinned[i].$1), y(thinned[i].$2));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = route.withValues(alpha: 0.1));
    canvas.drawPath(
      path,
      Paint()
        ..color = route
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );

    double altitudeAt(double d) {
      var lo = 0;
      while (lo + 1 < known.length && known[lo + 1].$1 < d) {
        lo++;
      }
      return known[lo].$2;
    }

    for (final s in stops) {
      final p = Offset(x(s.alongM), y(altitudeAt(s.alongM)));
      canvas.drawCircle(p, 4, Paint()..color = alt);
      canvas.drawCircle(
        p,
        4,
        Paint()
          ..color = surface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    final cd = cursorD;
    if (cd != null) {
      canvas.drawLine(
        Offset(x(cd), 0),
        Offset(x(cd), size.height),
        Paint()
          ..color = ink
          ..strokeWidth = 1.5,
      );
      final p = Offset(x(cd), y(altitudeAt(cd)));
      canvas.drawCircle(p, 5, Paint()..color = brand);
      canvas.drawCircle(
        p,
        5,
        Paint()
          ..color = surface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_ProfilePainter old) =>
      old.known != known || old.cursorD != cursorD || old.segments != segments || old.stops != stops;
}

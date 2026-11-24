import 'package:material_ui/material_ui.dart';

import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_theme.dart';
import '../../trail/domain/gps_coordinate.dart';
import '../application/plan_controller.dart';
import '../domain/route_profile.dart';

const double _padTop = 6;

/// Elevation against distance, with each stretch filled by how steep it is. Scrub to read a point.
class SteepnessProfile extends StatefulWidget {
  const SteepnessProfile({
    super.key,
    required this.coordinates,
    required this.t,
    this.checkpoints = const [],
    this.onCursor,
  });

  final List<GpsCoordinate> coordinates;
  final TFunction t;

  /// Marked on the distance axis, with the same labels as the map pins.
  final List<GpsCoordinate> checkpoints;

  /// Called with the point under the finger, or null when it leaves.
  final void Function(GpsCoordinate? point)? onCursor;

  @override
  State<SteepnessProfile> createState() => _SteepnessProfileState();
}

class _SteepnessProfileState extends State<SteepnessProfile> {
  ProfilePoint? _cursor;

  void _move(double dx, double width, RouteProfile profile) {
    final frac = (dx / width).clamp(0.0, 1.0);
    final p = pointAtProfile(profile, frac * profile.totalM);
    setState(() => _cursor = p);
    widget.onCursor?.call(p.coordinate);
  }

  void _leave() {
    setState(() => _cursor = null);
    widget.onCursor?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final c = context.colors;
    final profile = buildProfile(widget.coordinates);
    if (profile == null) return const SizedBox.shrink();
    final marks = checkpointDistances(profile, widget.checkpoints);
    final steepest = profile.bins.map((b) => b.gradePct.abs()).reduce((a, b) => a > b ? a : b);
    final cursor = _cursor;
    final grade = cursor == null ? null : binAt(profile, cursor.d).gradePct.round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(t('profile.title'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            if (cursor != null && grade != null)
              Flexible(
                child: Text(
                  t('profile.readout', {
                    'd': formatDistance(cursor.d),
                    'alt': formatElevation(cursor.alt),
                    'grade': '${grade > 0 ? '+' : ''}$grade',
                  }),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.inkSoft),
                ),
              )
            else
              Text(
                '${formatElevation(profile.minAlt)} – ${formatElevation(profile.maxAlt)}',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, box) {
            return Semantics(
              label: t('profile.alt', {
                'min': profile.minAlt.round(),
                'max': profile.maxAlt.round(),
                'steepest': steepest.round(),
              }),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (d) => _move(d.localPosition.dx, box.maxWidth, profile),
                onHorizontalDragUpdate: (d) => _move(d.localPosition.dx, box.maxWidth, profile),
                onHorizontalDragEnd: (_) => _leave(),
                onTapDown: (d) => _move(d.localPosition.dx, box.maxWidth, profile),
                onTapUp: (_) => _leave(),
                child: SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CustomPaint(painter: _SteepnessPainter(profile, marks, cursor?.d, c)),
                        ),
                      ),
                      for (var i = 0; i < marks.length; i++)
                        Positioned(
                          left: ((marks[i] / profile.totalM * 100).clamp(3, 97) / 100) * box.maxWidth - 8,
                          top: 2,
                          child: Container(
                            width: 16,
                            height: 16,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.ink),
                            ),
                            child: Text(
                              checkpointLabel(i),
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0', style: TextStyle(fontSize: 11, color: c.muted)),
            Flexible(
              child: Wrap(
                spacing: 10,
                runSpacing: 2,
                alignment: WrapAlignment.center,
                children: [
                  for (var i = 0; i <= gradeSteps.length; i++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: c.grades[i], borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          i == 0
                              ? '< ${gradeSteps[0].round()}%'
                              : (i < gradeSteps.length
                                    ? '${gradeSteps[i - 1].round()}–${gradeSteps[i].round()}%'
                                    : '> ${gradeSteps.last.round()}%'),
                          style: TextStyle(fontSize: 11, color: c.muted),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Text(formatDistance(profile.totalM), style: TextStyle(fontSize: 11, color: c.muted)),
          ],
        ),
      ],
    );
  }
}

class _SteepnessPainter extends CustomPainter {
  _SteepnessPainter(this.profile, this.marks, this.cursorD, this.colors);

  final RouteProfile profile;
  final List<double> marks;
  final double? cursorD;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.canvas);
    final range = profile.maxAlt - profile.minAlt == 0 ? 1.0 : profile.maxAlt - profile.minAlt;
    double x(double d) => d / profile.totalM * size.width;
    double y(double alt) => _padTop + (1 - (alt - profile.minAlt) / range) * (size.height - _padTop);

    for (final b in profile.bins) {
      final inside = profile.points.where((p) => p.d > b.from && p.d < b.to);
      final path = Path()..moveTo(x(b.from), size.height);
      path.lineTo(x(b.from), y(altAt(profile.points, b.from)));
      for (final p in inside) {
        path.lineTo(x(p.d), y(p.alt));
      }
      path.lineTo(x(b.to), y(altAt(profile.points, b.to)));
      path.lineTo(x(b.to), size.height);
      path.close();
      canvas.drawPath(path, Paint()..color = colors.grades[gradeClass(b.gradePct)]);
    }

    final line = Path();
    for (var i = 0; i < profile.points.length; i++) {
      final p = profile.points[i];
      i == 0 ? line.moveTo(x(p.d), y(p.alt)) : line.lineTo(x(p.d), y(p.alt));
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = colors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );

    for (final d in marks) {
      canvas.drawLine(
        Offset(x(d), 0),
        Offset(x(d), size.height),
        Paint()
          ..color = colors.ink
          ..strokeWidth = 1,
      );
    }
    final cd = cursorD;
    if (cd != null) {
      canvas.drawLine(
        Offset(x(cd), 0),
        Offset(x(cd), size.height),
        Paint()
          ..color = colors.ink
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_SteepnessPainter old) => old.profile != profile || old.cursorD != cursorD || old.marks != marks;
}

/// Placeholder with the profile's layout, shown while the route is being computed.
class SteepnessProfileSkeleton extends StatelessWidget {
  const SteepnessProfileSkeleton({super.key, required this.t});

  final TFunction t;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: t('profile.loading'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('profile.title'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            height: 80,
            decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(8)),
          ),
        ],
      ),
    );
  }
}

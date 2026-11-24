import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';

/// Splash screen: a terrain "map" made of particles that scatter in, assemble, and slowly rotate
/// in 3D, with a glowing trail running over the hills.
class SplashView extends StatefulWidget {
  const SplashView({super.key, this.replay = false});

  /// When true (opened from settings) the screen pops back instead of going to Home, and a tap closes it.
  final bool replay;

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 3600);
  late final AnimationController _controller = AnimationController(vsync: this, duration: _total);

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (!mounted) return;
      if (widget.replay) {
        _close();
      } else {
        context.go(Routes.home);
      }
    });
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.settings);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.replay ? _close : null,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final fade = t > 0.88 ? 1 - (t - 0.88) / 0.12 : 1.0;
            return Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _TerrainPainter(
                      seconds: t * _total.inMilliseconds / 1000,
                      progress: t,
                      color: scheme.primary,
                      accent: scheme.tertiary,
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.72),
                    child: Opacity(
                      opacity: Curves.easeIn.transform(((t - 0.35) / 0.3).clamp(0.0, 1.0)),
                      child: Text(
                        'Pania',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w300, letterSpacing: 8),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TerrainPainter extends CustomPainter {
  _TerrainPainter({required this.seconds, required this.progress, required this.color, required this.accent});

  final double seconds;
  final double progress;
  final Color color;
  final Color accent;

  static const _n = 56;
  static const _trailCount = 90;
  static const _buckets = 5;

  static double _height(double x, double z) {
    final r = math.sqrt(x * x + z * z);
    final hills =
        math.sin(x * 3.1 + 0.7) * math.cos(z * 2.7 - 0.4) * 0.5 +
        math.sin(x * 5.9 - z * 4.3) * 0.2 +
        math.cos(z * 7.3 + x * 1.9) * 0.1;
    final falloff = (1 - r * r).clamp(0.0, 1.0);
    return (hills + 0.35) * falloff;
  }

  static Offset _trail(double u) {
    final a = u * math.pi * 2.2 + 0.4;
    final r = 0.15 + 0.6 * u;
    return Offset(math.cos(a) * r, math.sin(a) * r * 0.9);
  }

  static double _rand(int i, int salt) {
    final v = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.42;
    final scale = size.shortestSide * 0.62;
    final assemble = Curves.easeOutCubic.transform((progress / 0.5).clamp(0.0, 1.0));
    final yaw = -0.9 + seconds * 0.45;
    const tilt = 1.0;
    final cosY = math.cos(yaw), sinY = math.sin(yaw);
    final cosT = math.cos(tilt), sinT = math.sin(tilt);
    const camera = 3.2;

    ({double x, double y, double depth})? project(double x, double y, double z) {
      final rx = x * cosY - z * sinY;
      final rz = x * sinY + z * cosY;
      final ry = y * cosT - rz * sinT;
      final rz2 = y * sinT + rz * cosT;
      final d = camera + rz2;
      if (d <= 0.2) return null;
      final p = camera / d;
      return (x: cx + rx * scale * p, y: cy - ry * scale * p, depth: ((rz2 + 1.5) / 3).clamp(0.0, 0.999));
    }

    final lists = List.generate(_buckets, (_) => <double>[]);

    for (var i = 0; i < _n; i++) {
      for (var j = 0; j < _n; j++) {
        final idx = i * _n + j;
        final gx = (i / (_n - 1)) * 2 - 1;
        final gz = (j / (_n - 1)) * 2 - 1;
        if (gx * gx + gz * gz > 1.05) continue;
        final wave = math.sin(seconds * 1.6 + gx * 4 + gz * 3) * 0.025;
        final h = (_height(gx, gz) + wave) * 0.55;

        final sx = (_rand(idx, 1) - 0.5) * 5;
        final sy = (_rand(idx, 2) - 0.5) * 3;
        final sz = (_rand(idx, 3) - 0.5) * 5;
        final p = project(
          ui.lerpDouble(sx, gx, assemble)!,
          ui.lerpDouble(sy, h, assemble)!,
          ui.lerpDouble(sz, gz, assemble)!,
        );
        if (p == null) continue;
        final b = (p.depth * _buckets).floor().clamp(0, _buckets - 1);
        lists[b]
          ..add(p.x)
          ..add(p.y);
      }
    }

    for (var b = _buckets - 1; b >= 0; b--) {
      final pts = lists[b];
      if (pts.isEmpty) continue;
      final near = 1 - b / (_buckets - 1);
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.2 + near * 2.2
        ..color = color.withValues(alpha: (0.25 + near * 0.6) * assemble.clamp(0.2, 1.0));
      canvas.drawRawPoints(ui.PointMode.points, Float32List.fromList(pts), paint);
    }

    final trailAppear = ((progress - 0.35) / 0.3).clamp(0.0, 1.0);
    if (trailAppear > 0) {
      final head = (seconds * 0.35) % 1.0;
      for (var i = 0; i < _trailCount; i++) {
        final u = i / (_trailCount - 1);
        if (u > trailAppear) break;
        final t2 = _trail(u);
        final h = _height(t2.dx, t2.dy) * 0.55 + 0.04;
        final p = project(t2.dx, h, t2.dy);
        if (p == null) continue;
        var d = head - u;
        if (d < 0) d += 1;
        final glow = math.exp(-d * 9);
        final paint = Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.5 + glow * 4
          ..color = accent.withValues(alpha: (0.45 + glow * 0.55).clamp(0.0, 1.0));
        canvas.drawPoints(ui.PointMode.points, [Offset(p.x, p.y)], paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TerrainPainter old) => old.seconds != seconds || old.color != color || old.accent != accent;
}

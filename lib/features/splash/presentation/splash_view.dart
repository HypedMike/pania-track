import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import 'pania_terrain.dart';

/// Splash screen: Pania della Croce, built from real elevation data as particles that scatter in,
/// assemble, and slowly rotate in 3D, with a glowing trail climbing to the summit.
class SplashView extends StatefulWidget {
  const SplashView({super.key, this.replay = false});

  /// When true (opened from settings) the screen stays open after the animation, letting the user
  /// rotate and zoom the 3D shape, and shows a close button instead of going to Home.
  final bool replay;

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with TickerProviderStateMixin {
  static const _total = Duration(milliseconds: 3600);
  late final AnimationController _controller = AnimationController(vsync: this, duration: _total);

  /// Keeps the scene alive (slow rotation, trail glow) after the intro in replay mode.
  final ValueNotifier<double> _idleSeconds = ValueNotifier(0);
  Ticker? _idleTicker;

  PaniaTerrain? _terrain;

  // User camera controls (replay mode only).
  double _yawOffset = 0;
  double _tiltOffset = 0;
  double _zoom = 1;
  double _startZoom = 1;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _onScaleStart(ScaleStartDetails d) => _startZoom = _zoom;

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _yawOffset += d.focalPointDelta.dx * 0.01;
      _tiltOffset = (_tiltOffset + d.focalPointDelta.dy * 0.01).clamp(-1.0, 0.55);
      _zoom = (_startZoom * d.scale).clamp(0.5, 3.5);
    });
  }

  void _resetView() => setState(() {
    _yawOffset = 0;
    _tiltOffset = 0;
    _zoom = 1;
  });

  Future<void> _start() async {
    try {
      _terrain = await PaniaTerrain.load();
    } catch (_) {
      // Without the terrain there is nothing to show: carry on to the app.
    }
    if (!mounted) return;
    if (_terrain != null) await _controller.forward();
    if (!mounted) return;
    if (widget.replay) {
      // Stay on screen: keep the scene animating so the user can explore it.
      _idleTicker = createTicker((e) => _idleSeconds.value = e.inMicroseconds / 1e6)..start();
    } else {
      context.go(Routes.home);
    }
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
    _idleTicker?.dispose();
    _idleSeconds.dispose();
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
        onScaleStart: widget.replay ? _onScaleStart : null,
        onScaleUpdate: widget.replay ? _onScaleUpdate : null,
        onDoubleTap: widget.replay ? _resetView : null,
        child: AnimatedBuilder(
          animation: Listenable.merge([_controller, _idleSeconds]),
          builder: (context, _) {
            final t = _controller.value;
            final fade = !widget.replay && t > 0.88 ? 1 - (t - 0.88) / 0.12 : 1.0;
            final seconds = t * _total.inMilliseconds / 1000 + _idleSeconds.value;
            return Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _TerrainPainter(
                      terrain: _terrain,
                      seconds: seconds,
                      progress: t,
                      color: scheme.primary,
                      accent: scheme.tertiary,
                      yawOffset: _yawOffset,
                      tiltOffset: _tiltOffset,
                      zoom: _zoom,
                    ),
                  ),
                  if (widget.replay)
                    SafeArea(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: IconButton(icon: const Icon(Icons.close), onPressed: _close),
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
  _TerrainPainter({
    required this.terrain,
    required this.seconds,
    required this.progress,
    required this.color,
    required this.accent,
    this.yawOffset = 0,
    this.tiltOffset = 0,
    this.zoom = 1,
  });

  final PaniaTerrain? terrain;
  final double seconds;
  final double progress;
  final Color color;
  final Color accent;
  final double yawOffset;
  final double tiltOffset;
  final double zoom;

  static const _trailCount = 90;
  static const _buckets = 5;
  static const _bands = 3;

  /// Vertical size of the summit above the base, in the same units as the 2-wide ground square.
  /// The real relief is ~0.45; this exaggerates it so the peak reads from far away.
  static const _relief = 0.75;

  /// Island edge: the ground sinks to the base near the border of the circle.
  static double _edge(double x, double z) {
    final r = math.sqrt(x * x + z * z);
    final t = ((1 - r) / 0.25).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static double _height(PaniaTerrain terrain, double x, double z) => terrain.at(x, z) * _edge(x, z) * _relief;

  /// A path winding up from the south-west rim to the summit at the middle.
  static Offset _trail(double u) {
    final a = 2.4 + (1 - u) * math.pi * 1.6;
    final r = 0.9 * (1 - u) * (1 - u * 0.15);
    return Offset(math.cos(a) * r, math.sin(a) * r);
  }

  static double _rand(int i, int salt) {
    final v = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final terrain = this.terrain;
    if (terrain == null) return;
    final n = terrain.n;
    final cx = size.width / 2;
    final cy = size.height * 0.46;
    final scale = size.shortestSide * 0.62 * zoom;
    final assemble = Curves.easeOutCubic.transform((progress / 0.5).clamp(0.0, 1.0));
    final yaw = -0.9 + seconds * 0.45 + yawOffset;
    final tilt = 1.0 + tiltOffset;
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

    // [depth bucket][elevation band] -> flat x,y pairs.
    final lists = List.generate(_buckets * _bands, (_) => <double>[]);
    // The base sits at height 0, so centre the whole shape vertically around its mid-height.
    const lift = -_relief * 0.4;

    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        final idx = i * n + j;
        final gx = (j / (n - 1)) * 2 - 1;
        final gz = (i / (n - 1)) * 2 - 1;
        if (gx * gx + gz * gz > 1.0) continue;
        final e = terrain.cell(i, j);
        final wave = math.sin(seconds * 1.6 + gx * 4 + gz * 3) * 0.012 * assemble;
        final h = _height(terrain, gx, gz) + wave + lift;

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
        final band = (e * _edge(gx, gz) * _bands * 1.15).floor().clamp(0, _bands - 1);
        lists[b * _bands + band]
          ..add(p.x)
          ..add(p.y);
      }
    }

    for (var b = _buckets - 1; b >= 0; b--) {
      final near = 1 - b / (_buckets - 1);
      for (var band = 0; band < _bands; band++) {
        final pts = lists[b * _bands + band];
        if (pts.isEmpty) continue;
        // Higher ground is drawn brighter and a little bigger.
        final high = band / (_bands - 1);
        final paint = Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.1 + near * 2.0 + high * 0.8
          ..color = Color.lerp(
            color,
            accent,
            high * 0.55,
          )!.withValues(alpha: ((0.2 + near * 0.5 + high * 0.3) * assemble.clamp(0.2, 1.0)).clamp(0.0, 1.0));
        canvas.drawRawPoints(ui.PointMode.points, Float32List.fromList(pts), paint);
      }
    }

    final trailAppear = ((progress - 0.35) / 0.3).clamp(0.0, 1.0);
    if (trailAppear > 0) {
      final head = (seconds * 0.35) % 1.0;
      for (var i = 0; i < _trailCount; i++) {
        final u = i / (_trailCount - 1);
        if (u > trailAppear) break;
        final t2 = _trail(u);
        final h = _height(terrain, t2.dx, t2.dy) + lift + 0.03;
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
  bool shouldRepaint(_TerrainPainter old) =>
      old.seconds != seconds ||
      old.color != color ||
      old.accent != accent ||
      old.terrain != terrain ||
      old.yawOffset != yawOffset ||
      old.tiltOffset != tiltOffset ||
      old.zoom != zoom;
}

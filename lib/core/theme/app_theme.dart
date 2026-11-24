import 'package:material_ui/material_ui.dart';

/// The app's colour tokens, light and dark. Read them with `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.canvas,
    required this.surface,
    required this.ink,
    required this.inkSoft,
    required this.muted,
    required this.line,
    required this.lineStrong,
    required this.map,
    required this.onInk,
    required this.brand,
    required this.brandDark,
    required this.brandFg,
    required this.brandTint,
    required this.brandTintInk,
    required this.route,
    required this.routeTint,
    required this.routeInk,
    required this.danger,
    required this.alt,
    required this.warnTint,
    required this.warnInk,
    required this.grades,
  });

  final Color canvas;
  final Color surface;
  final Color ink;
  final Color inkSoft;
  final Color muted;
  final Color line;
  final Color lineStrong;
  final Color map;
  final Color onInk;

  /// Filled buttons (white text on top); [brandFg] is brand-coloured text, strokes and focus rings.
  final Color brand;
  final Color brandDark;
  final Color brandFg;
  final Color brandTint;
  final Color brandTintInk;
  final Color route;
  final Color routeTint;
  final Color routeInk;
  final Color danger;

  /// Amber: expert-grade routes and warnings.
  final Color alt;
  final Color warnTint;
  final Color warnInk;

  /// Steepness profile: < 8 %, 8–15 %, 15–25 %, > 25 % (lightness steps, not hue alone).
  final List<Color> grades;

  static const light = AppColors(
    canvas: Color(0xFFF6F7F4),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF16201B),
    inkSoft: Color(0xFF3A453F),
    muted: Color(0xFF56615A),
    line: Color(0xFFE3E8E1),
    lineStrong: Color(0xFFD5DBD3),
    map: Color(0xFFE6ECE1),
    onInk: Color(0xFFFFFFFF),
    brand: Color(0xFF127A4B),
    brandDark: Color(0xFF0D5C38),
    brandFg: Color(0xFF127A4B),
    brandTint: Color(0xFFE3F1E9),
    brandTintInk: Color(0xFF0D5C38),
    route: Color(0xFF2F6FDB),
    routeTint: Color(0xFFE4ECFB),
    routeInk: Color(0xFF1E4FB8),
    danger: Color(0xFFC2410C),
    alt: Color(0xFFB45309),
    warnTint: Color(0xFFFEF3E2),
    warnInk: Color(0xFF92400E),
    grades: [Color(0xFFBFE3CD), Color(0xFFF2CF5B), Color(0xFFE07B39), Color(0xFF9F2F1C)],
  );

  static const dark = AppColors(
    canvas: Color(0xFF0F1512),
    surface: Color(0xFF18201C),
    ink: Color(0xFFE8EDE9),
    inkSoft: Color(0xFFC3CCC6),
    muted: Color(0xFF9AA59E),
    line: Color(0xFF252E2A),
    lineStrong: Color(0xFF2C3631),
    map: Color(0xFF1C2520),
    onInk: Color(0xFF0F1512),
    brand: Color(0xFF127A4B),
    brandDark: Color(0xFF0D5C38),
    brandFg: Color(0xFF4CC38A),
    brandTint: Color(0xFF163325),
    brandTintInk: Color(0xFF7FD9A8),
    route: Color(0xFF6A9BF0),
    routeTint: Color(0xFF1B2A47),
    routeInk: Color(0xFF9DBBF5),
    danger: Color(0xFFC2410C),
    alt: Color(0xFFF59E0B),
    warnTint: Color(0xFF3A2A12),
    warnInk: Color(0xFFFBBF77),
    grades: [Color(0xFF24553C), Color(0xFF8F7420), Color(0xFFD06A2E), Color(0xFFFF9B85)],
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => t < 0.5 ? this : (other as AppColors? ?? this);
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final scheme = ColorScheme.fromSeed(seedColor: c.brand, brightness: brightness).copyWith(
    primary: c.brand,
    onPrimary: Colors.white,
    surface: c.surface,
    onSurface: c.ink,
    outline: c.lineStrong,
    outlineVariant: c.line,
    error: c.danger,
    primaryContainer: c.brandTint,
    onPrimaryContainer: c.brandTintInk,
  );
  final base = ThemeData(brightness: brightness, colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    extensions: [c],
    dividerColor: c.line,
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(color: c.ink, fontSize: 16, fontWeight: FontWeight.w600),
      shape: Border(bottom: BorderSide(color: c.line)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size.fromHeight(50),
        side: BorderSide(color: c.lineStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.brandFg)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.brandFg, width: 2),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(color: c.onInk),
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1, thickness: 1),
  );
}

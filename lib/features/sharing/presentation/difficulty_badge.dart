import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../data/sharing_api.dart';

/// How hard a shared trail is, as the Rust core graded it.
class DifficultyBadge extends StatelessWidget {
  const DifficultyBadge(this.difficulty, {super.key, required this.t});

  final Difficulty difficulty;
  final TFunction t;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (difficulty) {
      Difficulty.easy => (c.brandTint, c.brandTintInk),
      Difficulty.moderate => (c.warnTint, c.warnInk),
      Difficulty.hard => (c.danger.withValues(alpha: 0.15), c.danger),
    };
    return Pill(t('difficulty.${difficulty.name}'), background: bg, foreground: fg);
  }
}

Color difficultyColor(BuildContext context, Difficulty d) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (d) {
    Difficulty.easy => dark ? const Color(0xFF4CC38A) : const Color(0xFF127A4B),
    Difficulty.moderate => dark ? const Color(0xFFF59E0B) : const Color(0xFFB45309),
    Difficulty.hard => dark ? const Color(0xFFF0836E) : const Color(0xFF9F2F1C),
  };
}

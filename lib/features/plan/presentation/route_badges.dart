import 'package:material_ui/material_ui.dart';

import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../domain/route_analysis.dart';

String _gradeLabel(CaiGrade g) => switch (g) {
  CaiGrade.t => 'T',
  CaiGrade.e => 'E',
  CaiGrade.ee => 'EE',
  CaiGrade.eea => 'EEA',
};

/// The CAI difficulty grade of a route.
class DifficultyChip extends StatelessWidget {
  const DifficultyChip(this.difficulty, {super.key, required this.t});

  final CaiGrade difficulty;
  final TFunction t;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final expert = difficulty == CaiGrade.ee || difficulty == CaiGrade.eea;
    return Pill(
      t('difficulty.${_gradeLabel(difficulty)}'),
      background: expert ? c.warnTint : c.brandTint,
      foreground: expert ? c.warnInk : c.brandTintInk,
    );
  }
}

class InfoChip extends StatelessWidget {
  const InfoChip(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Pill(text, background: context.colors.line, foreground: context.colors.inkSoft);
}

/// Gain and estimated time, the part of the summary after the distance: "+702 m · ~4h 10m".
String climbAndTime(RouteAnalysis a) =>
    '${formatElevation(a.gainM, signed: true)} · ~${formatDuration(a.estimatedMs.round())}';

/// "11.8 km · +702 m · ~4h 10m"
String routeLine(RouteAnalysis a) => '${formatDistance(a.distanceM)} · ${climbAndTime(a)}';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../analysis/data/analysis_api.dart';
import '../../analysis/presentation/analysis_widgets.dart';
import '../../analysis/presentation/format.dart';
import '../../trail/application/trail_controller.dart';
import '../../trail/domain/trail.dart';
import '../application/tour_controller.dart';
import '../data/tour_run_repository.dart';

class _ReviewData {
  const _ReviewData(this.run, this.trail, this.review);
  final TourRun run;
  final Trail trail;
  final Review? review;
}

final _reviewProvider = FutureProvider.autoDispose.family<_ReviewData, String>((ref, id) async {
  final runs = ref.read(tourRunRepositoryProvider);
  final run = await runs.get(id);
  if (run == null) throw Exception(I18n.t('review.notFound'));
  final trail = await ref.read(trailRepositoryProvider).getById(run.trailId);
  if (trail == null) throw Exception(I18n.t('error.trailNotFound'));
  final fixes = await runs.getFixes(id);
  final review = await AnalysisApi.reviewTour(
    trail.coordinates,
    fixes,
    Plan(speedMs: run.plannedSpeedMs, profile: run.planProfile),
  );
  return _ReviewData(run, trail, review);
});

/// A tour against its plan, kilometer by kilometer.
class TourReviewView extends ConsumerWidget {
  const TourReviewView({super.key, required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final data = ref.watch(_reviewProvider(runId));

    Widget page(Widget body) => PageScaffold(onBack: context.goBack, backLabel: t('detail.trails'), body: body);

    return data.when(
      loading: () => page(
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(t('analysis.working'), style: TextStyle(color: c.muted)),
          ),
        ),
      ),
      error: (e, _) => page(
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: ErrorText('$e'.replaceFirst('Exception: ', ''))),
        ),
      ),
      data: (d) {
        final review = d.review;
        final worst = review?.worstSplit == null ? null : review!.splits[review.worstSplit!.toInt()];
        final best = review?.bestSplit == null ? null : review!.splits[review.bestSplit!.toInt()];
        String range(double from, double to) => '${formatDistance(from)} → ${formatDistance(to)}';

        Future<void> remove() async {
          final ok = await confirmDialog(
            context,
            message: t('review.confirmDelete'),
            confirmLabel: t('review.delete'),
            cancelLabel: t('common.cancel'),
            destructive: true,
          );
          if (!ok) return;
          await ref.read(tourRunRepositoryProvider).remove(runId);
          if (context.mounted) context.goTo(Routes.trailDetail(d.trail.id), replace: true);
        }

        return page(
          PageColumn(
            gap: 14,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('review.title'),
                    style: const TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                    onPressed: () => context.goTo(Routes.trailDetail(d.trail.id)),
                    child: Text(
                      '${d.trail.name} · ${formatDate(DateTime.fromMillisecondsSinceEpoch(d.run.startedAt))}',
                    ),
                  ),
                ],
              ),
              if (review == null)
                Text(t('review.tooShort'), style: TextStyle(fontSize: 14, color: c.muted))
              else ...[
                AnalysisCard(
                  title: t('review.summary'),
                  aside: review.completed
                      ? t('review.completed')
                      : t('review.partial', {'d': formatDistance(review.coveredM)}),
                  children: [
                    FigureRow([
                      Figure(
                        label: t('review.planned'),
                        value: formatSeconds(review.plannedS),
                        hint: d.run.planProfile != null ? t('review.planSlope') : t('review.planFlat'),
                      ),
                      Figure(label: t('review.actual'), value: formatSeconds(review.actualS)),
                      Figure(label: t('review.difference'), value: formatDelta(review.deltaS)),
                    ]),
                    Text(
                      review.deltaS.abs() < 120
                          ? t('review.onPlan')
                          : t(review.deltaS > 0 ? 'review.behind' : 'review.ahead', {
                              'd': formatSeconds(review.deltaS.abs()),
                            }),
                      style: TextStyle(fontSize: 14, color: c.inkSoft),
                    ),
                    FigureRow([
                      Figure(label: t('analysis.moving'), value: formatSeconds(review.movingS)),
                      Figure(label: t('analysis.stopped'), value: formatSeconds(review.stoppedS)),
                      Figure(label: t('review.offTrail'), value: formatSeconds(review.offTrailS)),
                    ]),
                  ],
                ),
                AnalysisCard(
                  title: t('review.bySplit'),
                  aside: t('review.splitAxis'),
                  children: [
                    BarChart(
                      values: [for (final s in review.splits) s.deltaS / 60],
                      labels: [for (final s in review.splits) '${(s.toM / 100).round() / 10}'],
                      labelEvery: (review.splits.length / 8).ceil().clamp(1, 1000),
                      tones: [
                        for (final s in review.splits)
                          s.deltaS > 30 ? Tone.bad : (s.deltaS < -30 ? Tone.good : Tone.muted),
                      ],
                      height: 110,
                      semanticLabel: t('review.splitsAlt'),
                    ),
                    if (worst != null)
                      Text(
                        t('review.worst', {'range': range(worst.fromM, worst.toM), 'd': formatDelta(worst.deltaS)}),
                        style: TextStyle(fontSize: 14, color: c.inkSoft),
                      ),
                    if (best != null)
                      Text(
                        t('review.best', {'range': range(best.fromM, best.toM), 'd': formatDelta(best.deltaS)}),
                        style: TextStyle(fontSize: 14, color: c.inkSoft),
                      ),
                    for (var i = 0; i < review.splits.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: c.line),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    range(review.splits[i].fromM, review.splits[i].toM),
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    '${t('review.plannedActual', {'p': formatSeconds(review.splits[i].plannedS), 'a': formatSeconds(review.splits[i].actualS)})}'
                                    '${review.splits[i].stoppedS >= 60 ? ' · ${t('review.stopIn', {'d': formatSeconds(review.splits[i].stoppedS)})}' : ''}',
                                    style: TextStyle(fontSize: 12, color: c.muted),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  formatDelta(review.splits[i].deltaS),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: review.splits[i].deltaS > 30
                                        ? c.danger
                                        : (review.splits[i].deltaS < -30 ? c.brandFg : null),
                                  ),
                                ),
                                Text(
                                  formatDelta(review.splits[i].cumulativeDeltaS),
                                  style: TextStyle(fontSize: 12, color: c.muted),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              SmallButton(label: t('review.delete'), onPressed: remove),
            ],
          ),
        );
      },
    );
  }
}

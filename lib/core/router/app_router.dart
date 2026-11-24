import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/analysis/presentation/insights_view.dart';
import '../../features/analysis/presentation/trail_analysis_view.dart';
import '../../features/home/presentation/home_view.dart';
import '../../features/plan/presentation/plan_view.dart';
import '../../features/plan/presentation/route_variants_view.dart';
import '../../features/profile/presentation/create_profile_view.dart';
import '../../features/profile/presentation/import_profile_view.dart';
import '../../features/profile/presentation/profile_view.dart';
import '../../features/settings/presentation/settings_view.dart';
import '../../features/sharing/presentation/explore_view.dart';
import '../../features/sharing/presentation/nostr_settings_view.dart';
import '../../features/sharing/presentation/shared_trail_view.dart';
import '../../features/splash/presentation/splash_view.dart';
import '../../features/stats/presentation/stats_view.dart';
import '../../features/tiles/presentation/saved_tiles_view.dart';
import '../../features/tour/presentation/tour_review_view.dart';
import '../../features/tour/presentation/tour_view.dart';
import '../../features/trail/presentation/import_trail_view.dart';
import '../../features/trail/presentation/recording_view.dart';
import '../../features/trail/presentation/save_recording_view.dart';
import '../../features/trail/presentation/trail_detail_view.dart';
import '../ui/main_shell.dart';
import 'routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  GoRoute route(String path, Widget Function(GoRouterState state) build) =>
      GoRoute(path: path, builder: (context, state) => build(state));

  return GoRouter(
    initialLocation: Routes.splash,
    routes: [
      route(Routes.splash, (_) => const SplashView()),
      route(Routes.intro, (_) => const SplashView(replay: true)),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeView())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.explore, builder: (_, _) => const ExploreView())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.stats, builder: (_, _) => const StatsView())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.profile, builder: (_, _) => const ProfileView())],
          ),
        ],
      ),
      route(Routes.record, (_) => const RecordingView()),
      route(Routes.saveRecording, (_) => const SaveRecordingView()),
      route(Routes.importTrail, (_) => const ImportTrailView()),
      route(Routes.plan, (_) => const PlanView()),
      route(Routes.planRoutes, (_) => const RouteVariantsView()),
      route(Routes.profileCreate, (_) => const CreateProfileView()),
      route(Routes.profileImport, (_) => const ImportProfileView()),
      route(Routes.settings, (_) => const SettingsView()),
      route(Routes.nostrSettings, (_) => const NostrSettingsView()),
      route(Routes.savedTiles, (_) => const SavedTilesView()),
      route(Routes.insights, (_) => const InsightsView()),
      route(Routes.exploreTrailPattern, (s) => SharedTrailView(eventId: s.pathParameters['eventId']!)),
      route(Routes.trailDetailPattern, (s) => TrailDetailView(trailId: s.pathParameters['id']!)),
      route(Routes.tourPattern, (s) => TourView(trailId: s.pathParameters['id']!)),
      route(Routes.trailAnalysisPattern, (s) => TrailAnalysisView(trailId: s.pathParameters['id']!)),
      route(Routes.tourReviewPattern, (s) => TourReviewView(runId: s.pathParameters['id']!)),
    ],
  );
});

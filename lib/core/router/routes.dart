/// The app's routes. Paths with parameters have a builder next to them.
abstract final class Routes {
  static const home = '/';
  static const record = '/record';
  static const saveRecording = '/record/save';
  static const importTrail = '/import';
  static const plan = '/plan';
  static const planRoutes = '/plan/routes';
  static const profile = '/profile';
  static const profileCreate = '/profile/create';
  static const profileImport = '/profile/import';
  static const settings = '/settings';
  static const nostrSettings = '/settings/nostr';
  static const savedTiles = '/settings/tiles';
  static const explore = '/explore';
  static const stats = '/stats';
  static const insights = '/insights';

  static const exploreTrailPattern = '/explore/:eventId';
  static const trailDetailPattern = '/trails/:id';
  static const tourPattern = '/trails/:id/tour';
  static const trailAnalysisPattern = '/trails/:id/analysis';
  static const tourReviewPattern = '/tours/:id';

  static String trailDetail(String id) => '/trails/$id';
  static String exploreTrail(String eventId) => '/explore/$eventId';
  static String tour(String trailId) => '/trails/$trailId/tour';
  static String trailAnalysis(String trailId) => '/trails/$trailId/analysis';
  static String tourReview(String runId) => '/tours/$runId';
}

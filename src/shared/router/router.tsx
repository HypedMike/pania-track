import { createHashRouter } from "react-router";
import HomeView from "../../lib/home/views/home_view";
import ImportTrailView from "../../lib/trail/views/import_trail_view";
import PlanView from "../../lib/plan/views/plan_view";
import RouteVariantsView from "../../lib/plan/views/route_variants_view";
import ExploreView from "../../lib/sharing/views/explore_view";
import NostrSettingsView from "../../lib/sharing/views/nostr_settings_view";
import SharedTrailView from "../../lib/sharing/views/shared_trail_view";
import CreateProfileView from "../../lib/profile/views/create_profile_view";
import ImportProfileView from "../../lib/profile/views/import_profile_view";
import ProfileView from "../../lib/profile/views/profile_view";
import RecordingView from "../../lib/trail/views/recording_view";
import SaveRecordingView from "../../lib/trail/views/save_recording_view";
import StatsView from "../../lib/stats/views/stats_view";
import SettingsView from "../../lib/settings/views/settings_view";
import TrailDetailView from "../../lib/trail/views/trail_detail_view";
import TourView from "../../lib/tour/views/tour_view";
import { ROUTES } from "./routes";

export const router = createHashRouter([
  { path: ROUTES.home, element: <HomeView /> },
  { path: ROUTES.record, element: <RecordingView /> },
  { path: ROUTES.saveRecording, element: <SaveRecordingView /> },
  { path: ROUTES.importTrail, element: <ImportTrailView /> },
  { path: ROUTES.plan, element: <PlanView /> },
  { path: ROUTES.planRoutes, element: <RouteVariantsView /> },
  { path: ROUTES.profile, element: <ProfileView /> },
  { path: ROUTES.profileCreate, element: <CreateProfileView /> },
  { path: ROUTES.profileImport, element: <ImportProfileView /> },
  { path: ROUTES.settings, element: <SettingsView /> },
  { path: ROUTES.nostrSettings, element: <NostrSettingsView /> },
  { path: ROUTES.explore, element: <ExploreView /> },
  { path: ROUTES.exploreTrail, element: <SharedTrailView /> },
  { path: ROUTES.stats, element: <StatsView /> },
  { path: ROUTES.trailDetail, element: <TrailDetailView /> },
  { path: ROUTES.tour, element: <TourView /> },
]);

import { createHashRouter } from "react-router";
import HomeView from "../../lib/home/views/home_view";
import ImportTrailView from "../../lib/trail/views/import_trail_view";
import RecordingView from "../../lib/trail/views/recording_view";
import SaveRecordingView from "../../lib/trail/views/save_recording_view";
import SettingsView from "../../lib/settings/views/settings_view";
import TrailDetailView from "../../lib/trail/views/trail_detail_view";
import { ROUTES } from "./routes";

export const router = createHashRouter([
  { path: ROUTES.home, element: <HomeView /> },
  { path: ROUTES.record, element: <RecordingView /> },
  { path: ROUTES.saveRecording, element: <SaveRecordingView /> },
  { path: ROUTES.importTrail, element: <ImportTrailView /> },
  { path: ROUTES.settings, element: <SettingsView /> },
  { path: ROUTES.trailDetail, element: <TrailDetailView /> },
]);

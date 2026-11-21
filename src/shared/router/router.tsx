import { createHashRouter } from "react-router";
import HomeView from "../../lib/home/views/home_view";
import CreateTrailView from "../../lib/trail/views/create_trail_view";
import TrailDetailView from "../../lib/trail/views/trail_detail_view";
import { ROUTES } from "./routes";

export const router = createHashRouter([
  { path: ROUTES.home, element: <HomeView /> },
  { path: ROUTES.createTrail, element: <CreateTrailView /> },
  { path: ROUTES.trailDetail, element: <TrailDetailView /> },
]);

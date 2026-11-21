import { createHashRouter } from "react-router";
import HomeView from "../../lib/home/views/home_view";
import { ROUTES } from "./routes";

export const router = createHashRouter([
  { path: ROUTES.home, element: <HomeView /> },
]);

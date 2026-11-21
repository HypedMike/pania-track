import { useCallback, useMemo } from "react";
import { useNavigate, type NavigateOptions } from "react-router";
import type { AppRoute } from "./routes";

type Direction = "forward" | "back";

/** Read by the route-transition rules in index.css to pick the slide direction. */
function setDirection(direction: Direction) {
  document.documentElement.dataset.navDirection = direction;
}

export function useNavigation() {
  const navigate = useNavigate();

  const goTo = useCallback(
    (route: AppRoute, options?: NavigateOptions) => {
      setDirection("forward");
      return navigate(route, { viewTransition: true, ...options });
    },
    [navigate],
  );
  // React Router runs the view transition itself when history goes back to a page it
  // previously transitioned away from, so all we do is flag the direction. Starting our
  // own document.startViewTransition here collides with it and the flag gets reset early.
  const goBack = useCallback(() => {
    setDirection("back");
    return navigate(-1);
  }, [navigate]);
  const goForward = useCallback(() => {
    setDirection("forward");
    return navigate(1);
  }, [navigate]);

  return useMemo(
    () => ({ goTo, goBack, goForward }),
    [goTo, goBack, goForward],
  );
}

import { useCallback, useMemo } from "react";
import { useNavigate, type NavigateOptions } from "react-router";
import type { AppRoute } from "./routes";

type Direction = "forward" | "back";

function setDirection(direction: Direction) {
  document.documentElement.dataset.navDirection = direction;
}

/**
 * Resolves once the DOM under #root has changed and settled (no mutations for
 * `quietMs`), or after `maxMs` as a safety net. React Router renders route
 * changes asynchronously, so we can't know exactly when the new page is in.
 */
function waitForRender(start: () => void, quietMs = 60, maxMs = 800) {
  return new Promise<void>((resolve) => {
    const root = document.getElementById("root") ?? document.body;
    let quietTimer: number | undefined;
    const done = () => {
      observer.disconnect();
      window.clearTimeout(quietTimer);
      window.clearTimeout(maxTimer);
      resolve();
    };
    const observer = new MutationObserver(() => {
      window.clearTimeout(quietTimer);
      quietTimer = window.setTimeout(done, quietMs);
    });
    const maxTimer = window.setTimeout(done, maxMs);
    observer.observe(root, { childList: true, subtree: true });
    start();
  });
}

/** Run `navigate` inside a view transition tagged as a backward navigation. */
function backTransition(navigate: () => void) {
  setDirection("back");
  if (!document.startViewTransition) {
    navigate();
    return;
  }
  const transition = document.startViewTransition(() => waitForRender(navigate));
  transition.finished.finally(() => setDirection("forward"));
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
  const goBack = useCallback(
    () => backTransition(() => navigate(-1)),
    [navigate],
  );
  const goForward = useCallback(() => navigate(1), [navigate]);

  return useMemo(
    () => ({ goTo, goBack, goForward }),
    [goTo, goBack, goForward],
  );
}

import { useCallback, useMemo } from "react";
import { useNavigate, type NavigateOptions } from "react-router";
import type { AppRoute } from "./routes";

export function useNavigation() {
  const navigate = useNavigate();

  const goTo = useCallback(
    (route: AppRoute, options?: NavigateOptions) => navigate(route, options),
    [navigate],
  );
  const goBack = useCallback(() => navigate(-1), [navigate]);
  const goForward = useCallback(() => navigate(1), [navigate]);

  return useMemo(
    () => ({ goTo, goBack, goForward }),
    [goTo, goBack, goForward],
  );
}

import { useT } from "../../i18n/i18n";
import { ROUTES } from "../../router/routes";
import { useNavigation } from "../../router/use_navigation";

type Tab = "trails" | "explore" | "stats" | "profile";

const ICONS: Record<Tab, React.ReactNode> = {
  trails: <path d="M3 20l6-12 4 6 3-4 5 10z" strokeLinejoin="round" />,
  explore: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M15.5 8.5l-2 5-5 2 2-5z" strokeLinejoin="round" />
    </>
  ),
  stats: <path d="M5 20V12M12 20V5M19 20v-9" />,
  profile: (
    <>
      <circle cx="12" cy="8" r="4" />
      <path d="M4 21c1-4.5 4.5-6.5 8-6.5s7 2 8 6.5" />
    </>
  ),
};

/** Bottom tab bar switching between the trail list, explore, stats and the profile. */
function BottomNav({ current }: { current: Tab }) {
  const t = useT();
  const { goTo } = useNavigation();
  const tabs: { id: Tab; label: string; route: typeof ROUTES.home | typeof ROUTES.explore | typeof ROUTES.stats | typeof ROUTES.profile }[] = [
    { id: "trails", label: t("nav.trails"), route: ROUTES.home },
    { id: "explore", label: t("nav.explore"), route: ROUTES.explore },
    { id: "stats", label: t("nav.stats"), route: ROUTES.stats },
    { id: "profile", label: t("nav.profile"), route: ROUTES.profile },
  ];

  return (
    <nav
      aria-label={t("nav.label")}
      style={{ viewTransitionName: "bottom-nav" }}
      className="sticky bottom-0 z-[1000] grid grid-cols-4 border-t border-line bg-surface px-5 pt-2 pb-5"
    >
      {tabs.map((tab) => {
        const active = tab.id === current;
        return (
          <button
            key={tab.id}
            type="button"
            aria-current={active ? "page" : undefined}
            onClick={() => {
              if (active) return;
              // Tabs switch instantly (no view transition), and the new tab starts at the top.
              window.scrollTo(0, 0);
              goTo(tab.route, { replace: true, viewTransition: false });
            }}
            className={`flex h-14 flex-col items-center justify-center gap-1 text-xs ${
              active ? "font-semibold text-brand-fg" : "font-medium text-muted"
            }`}
          >
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
              {ICONS[tab.id]}
            </svg>
            {tab.label}
          </button>
        );
      })}
    </nav>
  );
}

export default BottomNav;

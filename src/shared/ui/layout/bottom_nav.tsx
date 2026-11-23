import { useLayoutEffect } from "react";
import { useT } from "../../i18n/i18n";
import { ROUTES } from "../../router/routes";
import { useNavigation } from "../../router/use_navigation";

type Tab = "trails" | "stats" | "profile";

const ORDER: Tab[] = ["trails", "stats", "profile"];
/** How long the direction flag stays on <html>, so it only affects this transition. */
const DIRECTION_MS = 500;

const ICONS: Record<Tab, React.ReactNode> = {
  trails: <path d="M3 20l6-12 4 6 3-4 5 10z" strokeLinejoin="round" />,
  stats: <path d="M5 20V12M12 20V5M19 20v-9" />,
  profile: (
    <>
      <circle cx="12" cy="8" r="4" />
      <path d="M4 21c1-4.5 4.5-6.5 8-6.5s7 2 8 6.5" />
    </>
  ),
};

/** Bottom tab bar switching between the trail list, the stats screen and the profile. */
function BottomNav({ current }: { current: Tab }) {
  const t = useT();
  // On a tab switch the new page must be captured scrolled to the top, otherwise its header
  // jumps while sliding in (the previous tab may have been scrolled further than this one is tall).
  useLayoutEffect(() => {
    if (document.documentElement.dataset.tabDir) window.scrollTo(0, 0);
  }, []);
  const { goTo } = useNavigation();
  const tabs: { id: Tab; label: string; route: typeof ROUTES.home | typeof ROUTES.stats | typeof ROUTES.profile }[] = [
    { id: "trails", label: t("nav.trails"), route: ROUTES.home },
    { id: "stats", label: t("nav.stats"), route: ROUTES.stats },
    { id: "profile", label: t("nav.profile"), route: ROUTES.profile },
  ];

  return (
    <nav
      aria-label={t("nav.label")}
      style={{ viewTransitionName: "bottom-nav" }}
      className="sticky bottom-0 z-[1000] grid grid-cols-3 border-t border-line bg-surface px-5 pt-2 pb-5"
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
              // Read by the tab-slide rules in index.css to pick the slide direction.
              const root = document.documentElement;
              root.dataset.tabDir = ORDER.indexOf(tab.id) > ORDER.indexOf(current) ? "forward" : "back";
              setTimeout(() => delete root.dataset.tabDir, DIRECTION_MS);
              goTo(tab.route, { replace: true });
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

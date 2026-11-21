import { useT } from "../../i18n/i18n";
import { ROUTES } from "../../router/routes";
import { useNavigation } from "../../router/use_navigation";

type Tab = "trails" | "stats";

const ORDER: Tab[] = ["trails", "stats"];
/** How long the direction flag stays on <html>, so it only affects this transition. */
const DIRECTION_MS = 500;

const ICONS: Record<Tab, React.ReactNode> = {
  trails: <path d="M3 20l6-12 4 6 3-4 5 10z" strokeLinejoin="round" />,
  stats: <path d="M5 20V12M12 20V5M19 20v-9" />,
};

/** Bottom tab bar switching between the trail list and the stats screen. */
function BottomNav({ current }: { current: Tab }) {
  const t = useT();
  const { goTo } = useNavigation();
  const tabs: { id: Tab; label: string; route: typeof ROUTES.home | typeof ROUTES.stats }[] = [
    { id: "trails", label: t("nav.trails"), route: ROUTES.home },
    { id: "stats", label: t("nav.stats"), route: ROUTES.stats },
  ];

  return (
    <nav
      aria-label={t("nav.label")}
      style={{ viewTransitionName: "bottom-nav" }}
      className="sticky bottom-0 z-[1000] grid grid-cols-2 border-t border-line bg-surface px-5 pt-2 pb-5"
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

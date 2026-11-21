import logo from "../../../assets/icon/logo.png";
import { formatDistance } from "../../../shared/gps/trail_stats";

interface HomeHeaderProps {
  trailCount: number;
  totalDistanceM: number;
  onOpenSettings: () => void;
}

function HomeHeader({
  trailCount,
  totalDistanceM,
  onOpenSettings,
}: HomeHeaderProps) {
  return (
    <header className="flex items-end justify-between">
      <div className="flex flex-col gap-1">
        <div className="mb-1.5 flex items-center gap-1.5 text-brand-fg">
          <img src={logo} alt="" className="size-7 rounded-lg" />
          <span className="font-display text-xl font-bold tracking-tight">
            pania
          </span>
        </div>
        <h1 className="font-display text-[34px] leading-tight font-bold tracking-tight">
          Trails
        </h1>
        <p className="text-sm text-muted">
          {trailCount} {trailCount === 1 ? "trail" : "trails"} ·{" "}
          {formatDistance(totalDistanceM)} in total
        </p>
      </div>
      <button
        type="button"
        aria-label="Settings"
        onClick={onOpenSettings}
        className="flex size-11 items-center justify-center rounded-full border border-line-strong bg-surface"
      >
        <svg
          width="20"
          height="20"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          aria-hidden="true"
        >
          <path d="M4 7h10M18 7h2M4 17h4M12 17h8" />
          <circle cx="16" cy="7" r="2" />
          <circle cx="10" cy="17" r="2" />
        </svg>
      </button>
    </header>
  );
}

export default HomeHeader;

import type { ReactNode } from "react";

type PageHeaderProps = {
  title?: string;
  /** When provided, a back button is rendered on the left. */
  onBack?: () => void;
  backLabel?: string;
  /** Show the chevron icon next to the back label. */
  backIcon?: boolean;
  /** Optional content for the right-hand slot. */
  action?: ReactNode;
};

function PageHeader({
  title,
  onBack,
  backLabel,
  backIcon = true,
  action,
}: PageHeaderProps) {
  return (
    <header className="grid h-[calc(5rem+var(--safe-top))] shrink-0 grid-cols-[1fr_auto_1fr] items-center border-b border-line bg-surface px-3 pt-[calc(1.25rem+var(--safe-top))]">
      {onBack ? (
        <button
          type="button"
          onClick={onBack}
          className="flex h-11 items-center gap-1 px-2 text-left text-[15px] font-medium text-brand-fg"
        >
          {backIcon && (
            <svg
              width="18"
              height="18"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden="true"
            >
              <path d="M15 18l-6-6 6-6" />
            </svg>
          )}
          {backLabel}
        </button>
      ) : (
        <span />
      )}
      <h1 className="min-w-0 truncate text-center text-base font-semibold">
        {title}
      </h1>
      <div className="relative flex justify-end">{action}</div>
    </header>
  );
}

export default PageHeader;

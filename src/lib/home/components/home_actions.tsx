import { useT } from "../../../shared/i18n/i18n";

interface HomeActionsProps {
  recordDisabled: boolean;
  onRecord: () => void;
  onImport: () => void;
}

function HomeActions({ recordDisabled, onRecord, onImport }: HomeActionsProps) {
  const t = useT();
  return (
    <div className="flex flex-col gap-2">
      <div className="grid grid-cols-2 gap-3">
        <button
          type="button"
          onClick={onRecord}
          disabled={recordDisabled}
          className="flex h-[60px] items-center justify-center gap-2.5 rounded-2xl bg-brand text-base font-semibold text-white active:bg-brand-dark disabled:opacity-50"
        >
          <svg
            width="22"
            height="22"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            aria-hidden="true"
          >
            <circle cx="12" cy="12" r="9" />
            <circle cx="12" cy="12" r="4" fill="currentColor" stroke="none" />
          </svg>
          {t("home.record")}
        </button>
        <button
          type="button"
          onClick={onImport}
          className="flex h-[60px] items-center justify-center gap-2.5 rounded-2xl border border-line-strong bg-surface text-base font-semibold"
        >
          <svg
            width="22"
            height="22"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
          >
            <path d="M12 15V4M7 9l5-5 5 5" />
            <path d="M4 15v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4" />
          </svg>
          {t("home.import")}
        </button>
      </div>
      <p className="text-center text-[13px] text-muted">
        {t("home.actionsHint")}
      </p>
    </div>
  );
}

export default HomeActions;

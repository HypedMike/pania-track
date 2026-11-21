import { useT } from "../../../shared/i18n/i18n";

interface RecordingBannerProps {
  paused: boolean;
  onOpen: () => void;
}

function RecordingBanner({ paused, onOpen }: RecordingBannerProps) {
  const t = useT();
  return (
    <button
      type="button"
      onClick={onOpen}
      className="flex h-12 items-center justify-between rounded-2xl bg-danger px-4 text-sm font-semibold text-white"
    >
      <span className="flex items-center gap-2">
        <span
          className="size-2.5 animate-pulse rounded-full bg-white"
          aria-hidden="true"
        />
        {paused ? t("banner.paused") : t("banner.inProgress")}
      </span>
      <span>{t("banner.open")}</span>
    </button>
  );
}

export default RecordingBanner;

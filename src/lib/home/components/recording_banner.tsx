interface RecordingBannerProps {
  paused: boolean;
  onOpen: () => void;
}

function RecordingBanner({ paused, onOpen }: RecordingBannerProps) {
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
        {paused ? "Recording paused" : "Recording in progress"}
      </span>
      <span>Open</span>
    </button>
  );
}

export default RecordingBanner;

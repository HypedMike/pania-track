import { useT } from "../../../shared/i18n/i18n";
import type { TrailSource } from "../interfaces/trail";

const STYLE: Record<TrailSource, string> = {
  recorded: "bg-brand-tint text-brand-tint-ink",
  imported: "bg-route-tint text-route-ink",
  planned: "bg-line text-ink-soft",
};

const LABEL = {
  recorded: "trail.sourceRecorded",
  imported: "trail.sourceImported",
  planned: "trail.sourcePlanned",
} as const;

function SourceBadge({ source }: { source: TrailSource }) {
  const t = useT();
  return (
    <span className={`rounded-md px-2 py-0.5 text-xs font-semibold ${STYLE[source]}`}>{t(LABEL[source])}</span>
  );
}

export default SourceBadge;

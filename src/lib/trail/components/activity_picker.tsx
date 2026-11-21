import { useT } from "../../../shared/i18n/i18n";
import type { TrailActivity } from "../interfaces/trail";

export const ACTIVITIES: TrailActivity[] = ["foot", "bike"];

interface ActivityPickerProps {
  value: TrailActivity;
  onChange: (value: TrailActivity) => void;
}

/** Segmented control to choose whether a trail is done on foot or by bike. */
function ActivityPicker({ value, onChange }: ActivityPickerProps) {
  const t = useT();
  return (
    <div role="radiogroup" aria-label={t("activity.label")} className="flex flex-col gap-1.5">
      <span className="text-sm font-semibold">{t("activity.label")}</span>
      <div className="grid grid-cols-2 gap-2">
        {ACTIVITIES.map((a) => (
          <button
            key={a}
            type="button"
            role="radio"
            aria-checked={value === a}
            onClick={() => onChange(a)}
            className={`h-12 rounded-xl border text-base font-semibold ${
              value === a
                ? "border-brand bg-brand text-white"
                : "border-line-strong bg-surface text-ink"
            }`}
          >
            {t(`activity.${a}`)}
          </button>
        ))}
      </div>
    </div>
  );
}

export default ActivityPicker;

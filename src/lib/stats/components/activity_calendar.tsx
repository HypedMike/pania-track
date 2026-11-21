import { currentLocale, useT } from "../../../shared/i18n/i18n";
import { addDays, dayKey, startOfDay, startOfWeek } from "../stats_summary";

interface ActivityCalendarProps {
  /** First day shown and the first day after the last one shown. */
  start: Date;
  end: Date;
  now: Date;
  activeDays: Set<string>;
}

/** Monday-first grid of days; active days are filled, today is outlined. */
function ActivityCalendar({ start, end, now, activeDays }: ActivityCalendarProps) {
  const t = useT();
  const locale = currentLocale();
  const today = startOfDay(now);

  const leading = (start.getDay() + 6) % 7;
  const days: (Date | null)[] = Array.from({ length: leading }, () => null);
  for (let d = start; d < end; d = addDays(d, 1)) days.push(d);

  const monday = startOfWeek(now);
  const weekdays = Array.from({ length: 7 }, (_, i) =>
    addDays(monday, i).toLocaleDateString(locale, { weekday: "narrow" }),
  );
  const activeList = days
    .filter((d): d is Date => d !== null && activeDays.has(dayKey(d)))
    .map((d) => d.toLocaleDateString(locale, { month: "short", day: "numeric" }))
    .join(", ");

  return (
    <div className="flex flex-col gap-2 rounded-2xl border border-line bg-surface p-4">
      <div className="grid grid-cols-7 gap-1.5 text-center text-xs text-muted" aria-hidden="true">
        {weekdays.map((w, i) => (
          <span key={i}>{w}</span>
        ))}
      </div>
      <div
        role="img"
        aria-label={`${t("stats.calendarAlt")} ${activeList}`}
        className="grid grid-cols-7 gap-1.5"
      >
        {days.map((d, i) => {
          if (!d) return <div key={`pad-${i}`} />;
          const active = activeDays.has(dayKey(d));
          const isToday = d.getTime() === today.getTime();
          const future = d > today;
          const tone = active
            ? "bg-brand font-semibold text-white"
            : future
              ? "text-muted"
              : "bg-line text-ink-soft";
          return (
            <div
              key={d.getTime()}
              className={`flex h-[38px] items-center justify-center rounded-[10px] text-[13px] ${tone} ${
                isToday ? "font-semibold ring-2 ring-ink ring-inset" : ""
              }`}
            >
              {d.getDate()}
            </div>
          );
        })}
      </div>
    </div>
  );
}

export default ActivityCalendar;

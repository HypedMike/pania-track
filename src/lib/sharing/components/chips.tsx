/** A row of pill buttons: single choice (`selected` is one id) or toggles (`selected` is a list). */
function Chips<T extends string | number>({
  label,
  options,
  selected,
  onToggle,
}: {
  label: string;
  options: { id: T; label: string }[];
  selected: T[];
  onToggle: (id: T) => void;
}) {
  return (
    <div role="group" aria-label={label} className="flex flex-col gap-1.5">
      <span className="text-xs font-semibold text-muted">{label}</span>
      <div className="-mx-5 flex gap-2 overflow-x-auto px-5">
        {options.map((o) => {
          const on = selected.includes(o.id);
          return (
            <button
              key={o.id}
              type="button"
              aria-pressed={on}
              onClick={() => onToggle(o.id)}
              className={`h-11 shrink-0 rounded-full px-4 text-sm whitespace-nowrap ${
                on ? "bg-ink font-semibold text-on-ink" : "border border-line-strong bg-surface font-medium"
              }`}
            >
              {o.label}
            </button>
          );
        })}
      </div>
    </div>
  );
}

export default Chips;

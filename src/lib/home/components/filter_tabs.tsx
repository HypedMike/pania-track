import { useT } from "../../../shared/i18n/i18n";

export interface FilterTab<T extends string> {
  id: T;
  label: string;
  n: number;
}

interface FilterTabsProps<T extends string> {
  tabs: FilterTab<T>[];
  selected: T;
  onSelect: (id: T) => void;
}

function FilterTabs<T extends string>({
  tabs,
  selected,
  onSelect,
}: FilterTabsProps<T>) {
  const t = useT();
  return (
    <div className="-mx-5 flex gap-2 overflow-x-auto px-5" role="tablist" aria-label={t("home.filterLabel")}>
      {tabs.map((tab) => (
        <button
          key={tab.id}
          type="button"
          role="tab"
          aria-selected={selected === tab.id}
          onClick={() => onSelect(tab.id)}
          className={`h-11 shrink-0 rounded-full px-4 text-sm whitespace-nowrap ${
            selected === tab.id
              ? "bg-ink font-semibold text-on-ink"
              : "border border-line-strong bg-surface font-medium"
          }`}
        >
          {tab.label} · {tab.n}
        </button>
      ))}
    </div>
  );
}

export default FilterTabs;

import { useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import { searchPlaces, type Place, type PlaceKind } from "../../../shared/geocoding/photon";
import { useT } from "../../../shared/i18n/i18n";
import { useSettingsStore } from "../../../shared/settings/settings_store";
import { toast } from "sonner";
import type { GpsCoordinate } from "../../trail/interfaces/gps_coordinate";

const DEBOUNCE_MS = 300;
const MIN_CHARS = 2;

function KindIcon({ kind }: { kind: PlaceKind }) {
  const common = {
    width: 18,
    height: 18,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 2,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
  };
  if (kind === "peak") {
    return (
      <svg {...common}>
        <path d="M2 20l7-12 4 6 3-4 6 10z" />
      </svg>
    );
  }
  if (kind === "nature") {
    return (
      <svg {...common}>
        <path d="M12 3l6 9h-4l4 6H6l4-6H6z" />
        <path d="M12 18v3" />
      </svg>
    );
  }
  return (
    <svg {...common}>
      <path d="M12 21s-7-6.2-7-11.5a7 7 0 0 1 14 0C19 14.8 12 21 12 21z" />
      <circle cx="12" cy="9.5" r="2.5" />
    </svg>
  );
}

interface PlaceSearchProps {
  /** Results are ranked by distance from here (the map centre). */
  near?: () => GpsCoordinate | undefined;
  onSelect: (place: Place) => void;
  /** Called when the user clears the box. */
  onClear?: () => void;
  className?: string;
}

/** Search box with type-ahead results for towns, peaks and other places. */
function PlaceSearch({ near, onSelect, onClear, className }: PlaceSearchProps) {
  const t = useT();
  const language = useSettingsStore((s) => s.language);
  const listId = useId();
  const input = useRef<HTMLInputElement>(null);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Place[]>([]);
  const [status, setStatus] = useState<"idle" | "loading" | "done" | "error">("idle");
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);

  useEffect(() => {
    const q = query.trim();
    if (q.length < MIN_CHARS) {
      setResults([]);
      setStatus("idle");
      return;
    }
    const controller = new AbortController();
    setStatus("loading");
    const timer = setTimeout(async () => {
      try {
        const places = await searchPlaces(q, { near: near?.(), language, signal: controller.signal });
        setResults(places);
        setActive(0);
        setStatus("done");
      } catch (e) {
        if (controller.signal.aborted) return;
        const message = e instanceof Error ? e.message : String(e);
        setError(message);
        setStatus("error");
        toast.error(message, { id: message });
      }
    }, DEBOUNCE_MS);
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
    // `near` is read when the search runs; a new map position alone shouldn't search again.
  }, [query, language]);

  function choose(place: Place) {
    setQuery(place.name);
    setOpen(false);
    input.current?.blur();
    onSelect(place);
  }

  function onKeyDown(e: KeyboardEvent<HTMLInputElement>) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setOpen(true);
      setActive((i) => Math.min(i + 1, results.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((i) => Math.max(i - 1, 0));
    } else if (e.key === "Enter" && results[active]) {
      e.preventDefault();
      choose(results[active]);
    } else if (e.key === "Escape") {
      setOpen(false);
    }
  }

  const showList = open && query.trim().length >= MIN_CHARS && status !== "idle";

  return (
    <div className={`relative ${className ?? ""}`}>
      <div className="flex h-11 items-center gap-2 rounded-full bg-surface pr-1 pl-3.5 shadow-[0_2px_8px_rgb(22_32_27/0.12)]">
        <svg className="shrink-0 text-muted" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
          <circle cx="11" cy="11" r="7" />
          <path d="M20 20l-3.5-3.5" />
        </svg>
        <input
          ref={input}
          type="search"
          role="combobox"
          aria-label={t("search.label")}
          aria-expanded={showList}
          aria-controls={listId}
          aria-autocomplete="list"
          aria-activedescendant={showList && results[active] ? `${listId}-${active}` : undefined}
          placeholder={t("search.placeholder")}
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setOpen(true);
          }}
          onFocus={() => setOpen(true)}
          onBlur={() => setOpen(false)}
          onKeyDown={onKeyDown}
          enterKeyHint="search"
          autoComplete="off"
          className="h-full min-w-0 flex-1 bg-transparent text-[15px] text-ink placeholder:text-muted focus:outline-none [&::-webkit-search-cancel-button]:hidden"
        />
        {query && (
          <button
            type="button"
            onClick={() => {
              setQuery("");
              onClear?.();
              input.current?.focus();
            }}
            aria-label={t("search.clear")}
            className="flex size-9 shrink-0 items-center justify-center rounded-full text-muted"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" aria-hidden="true">
              <path d="M6 6l12 12M18 6L6 18" />
            </svg>
          </button>
        )}
      </div>

      {showList && (
        <div className="absolute inset-x-0 top-[52px] overflow-hidden rounded-2xl bg-surface shadow-[0_6px_24px_rgb(22_32_27/0.18)]">
          {status === "loading" && results.length === 0 && (
            <p className="px-4 py-3 text-sm text-muted">{t("search.searching")}</p>
          )}
          {status === "error" && <p className="px-4 py-3 text-sm text-danger">{error}</p>}
          {status === "done" && results.length === 0 && (
            <p className="px-4 py-3 text-sm text-muted">{t("search.noResults")}</p>
          )}
          {results.length > 0 && (
            <ul id={listId} role="listbox" aria-label={t("search.label")} className="max-h-72 overflow-y-auto">
              {results.map((place, i) => (
                <li
                  key={place.id}
                  id={`${listId}-${i}`}
                  role="option"
                  aria-selected={i === active}
                  // mousedown, not click: the input's blur would close the list first.
                  onMouseDown={(e) => {
                    e.preventDefault();
                    choose(place);
                  }}
                  onMouseEnter={() => setActive(i)}
                  className={`flex min-h-12 cursor-pointer items-center gap-3 border-line px-4 py-2 not-first:border-t ${
                    i === active ? "bg-canvas" : ""
                  }`}
                >
                  <span className="text-muted">
                    <KindIcon kind={place.kind} />
                  </span>
                  <span className="flex min-w-0 flex-col">
                    <span className="truncate text-[15px] font-medium">{place.name}</span>
                    <span className="truncate text-[13px] text-muted">
                      {place.kind === "peak" ? `${t("search.peak")} · ` : ""}
                      {place.context}
                    </span>
                  </span>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}

export default PlaceSearch;

import { useNavigation } from "../../../shared/router/use_navigation";
import {
  RECORD_INTERVALS_S,
  useSettingsStore,
  type ThemeSetting,
} from "../../../shared/settings/settings_store";
import { useRecordingStore } from "../../trail/stores/recording_store";

const THEMES: { id: ThemeSetting; label: string }[] = [
  { id: "system", label: "System" },
  { id: "light", label: "Light" },
  { id: "dark", label: "Dark" },
];

function intervalLabel(seconds: number): string {
  return seconds < 60 ? `${seconds} s` : `${seconds / 60} min`;
}

function Segmented<T extends string | number>({
  label,
  options,
  value,
  onChange,
}: {
  label: string;
  options: { id: T; label: string }[];
  value: T;
  onChange: (id: T) => void;
}) {
  return (
    <div role="radiogroup" aria-label={label} className="flex flex-wrap gap-2">
      {options.map((option) => {
        const active = option.id === value;
        return (
          <button
            key={option.id}
            type="button"
            role="radio"
            aria-checked={active}
            onClick={() => onChange(option.id)}
            className={`h-11 rounded-full px-4 text-sm ${
              active ? "bg-ink font-semibold text-on-ink" : "border border-line-strong bg-surface font-medium"
            }`}
          >
            {option.label}
          </button>
        );
      })}
    </div>
  );
}

function SettingsView() {
  const { goBack } = useNavigation();
  const { theme, recordIntervalS, setTheme, setRecordIntervalS } = useSettingsStore();
  const recording = useRecordingStore((s) => s.status === "recording");

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col">
      <header className="grid h-[60px] shrink-0 grid-cols-[88px_1fr_88px] items-center border-b border-line bg-surface px-3">
        <button type="button" onClick={goBack} className="flex h-11 items-center gap-1 px-2 text-[15px] font-medium text-brand-fg">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M15 18l-6-6 6-6" />
          </svg>
          Back
        </button>
        <h1 className="text-center text-base font-semibold">Settings</h1>
      </header>

      <div className="flex flex-col gap-6 px-5 pt-5 pb-6">
        <section className="flex flex-col gap-3 rounded-2xl border border-line bg-surface p-4">
          <div>
            <h2 className="text-sm font-semibold">Theme</h2>
            <p className="text-sm text-muted">System follows your device's light or dark setting.</p>
          </div>
          <Segmented label="Theme" options={THEMES} value={theme} onChange={setTheme} />
        </section>

        <section className="flex flex-col gap-3 rounded-2xl border border-line bg-surface p-4">
          <div>
            <h2 className="text-sm font-semibold">GPS recording frequency</h2>
            <p className="text-sm text-muted">
              How often a point is added to the track. Shorter intervals give a more detailed trail but use more
              battery and storage.
            </p>
          </div>
          <Segmented
            label="GPS recording frequency"
            options={RECORD_INTERVALS_S.map((s) => ({ id: s, label: intervalLabel(s) }))}
            value={recordIntervalS}
            onChange={setRecordIntervalS}
          />
          {recording && (
            <p className="text-sm text-muted">A recording is in progress; the new interval applies when it resumes.</p>
          )}
        </section>
      </div>
    </main>
  );
}

export default SettingsView;

import { useT } from "../../../shared/i18n/i18n";
import { LANGUAGES, type Language } from "../../../shared/i18n/translations";
import { useNavigation } from "../../../shared/router/use_navigation";
import {
  RECORD_INTERVALS_S,
  useSettingsStore,
  type ThemeSetting,
} from "../../../shared/settings/settings_store";
import PageHeader from "../../../shared/ui/layout/page_header";
import { useRecordingStore } from "../../trail/stores/recording_store";

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
              active
                ? "bg-ink font-semibold text-on-ink"
                : "border border-line-strong bg-surface font-medium"
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
  const t = useT();
  const {
    theme,
    language,
    recordIntervalS,
    setTheme,
    setLanguage,
    setRecordIntervalS,
  } = useSettingsStore();
  const themes: { id: ThemeSetting; label: string }[] = [
    { id: "system", label: t("settings.themeSystem") },
    { id: "light", label: t("settings.themeLight") },
    { id: "dark", label: t("settings.themeDark") },
  ];
  const recording = useRecordingStore((s) => s.status === "recording");

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col">
      <PageHeader
        title={t("settings.title")}
        onBack={goBack}
        backLabel={t("common.back")}
      />

      <div className="flex flex-col gap-6 px-5 pt-5 pb-6">
        <section className="flex flex-col gap-3 rounded-2xl border border-line bg-surface p-4">
          <div>
            <h2 className="text-sm font-semibold">{t("settings.theme")}</h2>
            <p className="text-sm text-muted">{t("settings.themeHint")}</p>
          </div>
          <Segmented
            label={t("settings.theme")}
            options={themes}
            value={theme}
            onChange={setTheme}
          />
        </section>

        <section className="flex flex-col gap-3 rounded-2xl border border-line bg-surface p-4">
          <div>
            <h2 className="text-sm font-semibold">
              <label htmlFor="language-select">{t("settings.language")}</label>
            </h2>
            <p className="text-sm text-muted">{t("settings.languageHint")}</p>
          </div>
          <select
            id="language-select"
            value={language}
            onChange={(e) => setLanguage(e.target.value as Language)}
            className="h-12 rounded-xl border border-line-strong bg-surface px-3.5 text-base text-ink focus:border-2 focus:border-brand-fg focus:outline-none"
          >
            {LANGUAGES.map((l) => (
              <option key={l.id} value={l.id}>
                {l.label}
              </option>
            ))}
          </select>
        </section>

        <section className="flex flex-col gap-3 rounded-2xl border border-line bg-surface p-4">
          <div>
            <h2 className="text-sm font-semibold">
              {t("settings.gpsFrequency")}
            </h2>
            <p className="text-sm text-muted">
              {t("settings.gpsFrequencyHint")}
            </p>
          </div>
          <Segmented
            label={t("settings.gpsFrequency")}
            options={RECORD_INTERVALS_S.map((s) => ({
              id: s,
              label: intervalLabel(s),
            }))}
            value={recordIntervalS}
            onChange={setRecordIntervalS}
          />
          {recording && (
            <p className="text-sm text-muted">
              {t("settings.recordingInProgress")}
            </p>
          )}
        </section>
      </div>
    </main>
  );
}

export default SettingsView;

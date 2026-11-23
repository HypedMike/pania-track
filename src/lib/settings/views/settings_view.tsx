import logo from "../../../assets/icon/logo.png";
import { openExternal, REPO_URL } from "../../../shared/app_info";
import { useT } from "../../../shared/i18n/i18n";
import { LANGUAGES, type Language } from "../../../shared/i18n/translations";
import { ROUTES } from "../../../shared/router/routes";
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

const CREDITS = [
  { name: "OpenStreetMap", url: "https://www.openstreetmap.org/copyright" },
  { name: "BRouter", url: "https://brouter.de" },
  { name: "Photon", url: "https://photon.komoot.io" },
];

/** A link that opens in the system browser. */
function ExternalLink({ href, children, className }: { href: string; children: React.ReactNode; className?: string }) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      onClick={(e) => {
        e.preventDefault();
        openExternal(href);
      }}
      className={className}
    >
      {children}
    </a>
  );
}

function SettingsView() {
  const { goBack, goTo } = useNavigation();
  const t = useT();
  const {
    theme,
    language,
    recordIntervalS,
    setTheme,
    setLanguage,
    setRecordIntervalS,
    checkForUpdates,
    setCheckForUpdates,
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

        <section className="flex flex-col gap-3 rounded-2xl border border-line bg-surface p-4">
          <div>
            <h2 className="text-sm font-semibold">{t("settings.updates")}</h2>
            <p className="text-sm text-muted">{t("settings.updatesHint")}</p>
          </div>
          <Segmented
            label={t("settings.updates")}
            options={[
              { id: "on", label: t("settings.on") },
              { id: "off", label: t("settings.off") },
            ]}
            value={checkForUpdates ? "on" : "off"}
            onChange={(id) => setCheckForUpdates(id === "on")}
          />
          <p className="text-sm text-muted">
            {t("settings.version", { version: __APP_VERSION__ })}
          </p>
        </section>

        <button
          type="button"
          onClick={() => goTo(ROUTES.nostrSettings)}
          className="flex min-h-14 items-center justify-between gap-3 rounded-2xl border border-line bg-surface p-4 text-left"
        >
          <span className="flex flex-col">
            <span className="text-sm font-semibold">{t("settings.nostr")}</span>
            <span className="text-sm text-muted">{t("settings.nostrHint")}</span>
          </span>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="shrink-0 text-muted">
            <path d="M9 6l6 6-6 6" />
          </svg>
        </button>

        <section aria-labelledby="about-title" className="flex flex-col gap-3 rounded-2xl border border-line bg-surface p-4">
          <div className="flex items-center gap-3">
            <img src={logo} alt="" className="size-12 shrink-0 rounded-xl" />
            <div className="min-w-0">
              <h2 id="about-title" className="text-sm font-semibold">
                {t("about.title")}
              </h2>
              <p className="text-sm text-muted">
                pania · {t("settings.version", { version: __APP_VERSION__ })}
              </p>
            </div>
          </div>
          <p className="text-sm text-ink-soft">{t("about.description")}</p>
          <p className="text-sm text-muted">{t("about.privacy")}</p>
          <ExternalLink
            href={REPO_URL}
            className="flex h-12 items-center justify-center gap-2 rounded-xl border border-line-strong text-[15px] font-semibold text-ink"
          >
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M8 6l-6 6 6 6M16 6l6 6-6 6" />
            </svg>
            {t("about.source")}
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5" />
            </svg>
          </ExternalLink>
          <p className="text-xs text-muted">
            {t("about.credits")}{" "}
            {CREDITS.map((c, i) => (
              <span key={c.name}>
                {i > 0 && " · "}
                <ExternalLink href={c.url} className="text-brand-fg underline underline-offset-2">
                  {c.name}
                </ExternalLink>
              </span>
            ))}
          </p>
        </section>
      </div>
    </main>
  );
}

export default SettingsView;

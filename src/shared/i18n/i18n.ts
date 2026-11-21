import { useCallback } from "react";
import { useSettingsStore } from "../settings/settings_store";
import { LANGUAGES, dictionaries, type Language, type TranslationKey } from "./translations";

type Params = Record<string, string | number>;
export type TFunction = (key: TranslationKey, params?: Params) => string;

export function translate(language: Language, key: TranslationKey, params?: Params): string {
  const text = dictionaries[language][key] ?? dictionaries.en[key];
  if (!params) return text;
  return text.replace(/\{(\w+)\}/g, (_, name: string) => String(params[name] ?? `{${name}}`));
}

/** Translate outside React components (errors, formatters). Uses the current language setting. */
export const t: TFunction = (key, params) => translate(useSettingsStore.getState().language, key, params);

/** BCP 47 locale for Intl / toLocale* formatting in the current language. */
export function currentLocale(): string {
  const language = useSettingsStore.getState().language;
  return LANGUAGES.find((l) => l.id === language)?.locale ?? "en-GB";
}

/** Singular/plural count label, e.g. plural("common.trail", 3) → "3 trails". */
export function plural(
  base: "common.waypoint" | "common.trail",
  n: number,
  translateFn: TFunction = t,
): string {
  return translateFn(`${base}.${n === 1 ? "one" : "other"}`, { n });
}

/** React hook: returns a `t` that re-renders the component when the language changes. */
export function useT(): TFunction {
  const language = useSettingsStore((s) => s.language);
  return useCallback((key, params) => translate(language, key, params), [language]);
}

/** Keeps <html lang> in sync with the setting. Call once at startup. */
export function initI18n() {
  const apply = () => {
    document.documentElement.lang = useSettingsStore.getState().language;
  };
  apply();
  useSettingsStore.subscribe(apply);
}

/// <reference types="vite/client" />

/** App version from package.json, injected at build time. */
declare const __APP_VERSION__: string;

interface ImportMetaEnv {
  /** GitHub "latest release" API URL used for update checks and the website. */
  readonly VITE_LATEST_RELEASE_URL?: string;
}

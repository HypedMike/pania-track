export interface LatestRelease {
  /** Plain X.Y.Z, without the leading "v". */
  version: string;
  /** Direct APK download, falling back to the release page. */
  downloadUrl: string;
  pageUrl: string;
}

/** Endpoint of the latest GitHub release, set through VITE_LATEST_RELEASE_URL. */
export const LATEST_RELEASE_URL: string | undefined = import.meta.env.VITE_LATEST_RELEASE_URL;

interface GithubRelease {
  tag_name: string;
  html_url: string;
  assets?: { name: string; browser_download_url: string }[];
}

export async function fetchLatestRelease(url: string, signal?: AbortSignal): Promise<LatestRelease> {
  const res = await fetch(url, { headers: { Accept: "application/vnd.github+json" }, signal });
  if (!res.ok) throw new Error(`Release lookup failed (${res.status})`);
  const data = (await res.json()) as GithubRelease;
  const apk = data.assets?.find((a) => a.name.endsWith(".apk"));
  return {
    version: data.tag_name.replace(/^v/, ""),
    downloadUrl: apk?.browser_download_url ?? data.html_url,
    pageUrl: data.html_url,
  };
}

/** True when `candidate` is a strictly newer X.Y.Z than `current`. */
export function isNewerVersion(candidate: string, current: string): boolean {
  const parse = (v: string) => v.replace(/^v/, "").split(".").map((n) => parseInt(n, 10) || 0);
  const a = parse(candidate);
  const b = parse(current);
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const d = (a[i] ?? 0) - (b[i] ?? 0);
    if (d !== 0) return d > 0;
  }
  return false;
}

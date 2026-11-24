import { useEffect, useState } from "react";
import {
  fetchLatestRelease,
  LATEST_RELEASE_URL,
  type LatestRelease,
} from "./latest_release";

const REPO = "https://github.com/HypedMike/pania-track";

const FEATURES = [
  {
    title: "Record",
    text: "GPS recording that keeps going with the screen off. Choose a sampling interval from 1 to 60 seconds.",
  },
  {
    title: "Import & export",
    text: "Open GPX and KML files, including Google Earth tracks, and share any trail as GPX.",
  },
  {
    title: "Plan",
    text: "Plan routes with alternatives and see a steepness profile before you set out.",
  },
  {
    title: "Explore",
    text: "OpenStreetMap-based maps with distance, duration and elevation stats for every trail.",
  },
  {
    title: "Private",
    text: "All data is stored locally in SQLite on your device and never leaves it.",
  },
  {
    title: "Open source",
    text: "Built with Flutter and Rust. Source and releases are on GitHub.",
  },
];

function App() {
  const [release, setRelease] = useState<LatestRelease | null>(null);

  useEffect(() => {
    if (!LATEST_RELEASE_URL) return;
    const controller = new AbortController();
    fetchLatestRelease(LATEST_RELEASE_URL, controller.signal)
      .then(setRelease)
      .catch(() => {
        /* keep the generic link */
      });
    return () => controller.abort();
  }, []);

  return (
    <div className="wrap">
      <header className="hero">
        <span className="brand">
          <img src={`${import.meta.env.BASE_URL}logo.png`} alt="" />
          Pania
        </span>
        <h1>
          Your trails, <i>on your device</i>.
        </h1>
        <p className="lead">
          A local-first trail recorder and viewer. Record hikes with GPS, import
          tracks, plan routes and browse them on a map. No account, no cloud.
        </p>
        <div className="btns">
          <a
            className="btn"
            href={release?.downloadUrl ?? `${REPO}/releases/latest`}
          >
            {release
              ? `Download Pania ${release.version} for Android`
              : "Download for Android"}
          </a>
          <a className="btn alt" href={REPO}>
            View on GitHub
          </a>
        </div>
        {release && (
          <p className="version">
            Latest version: <a href={release.pageUrl}>v{release.version}</a>
          </p>
        )}
      </header>

      <section className="grid">
        {FEATURES.map((f) => (
          <div className="card" key={f.title}>
            <h2>{f.title}</h2>
            <p>{f.text}</p>
          </div>
        ))}
      </section>

      <footer>
        Pania · <a href={REPO}>Source code</a> ·{" "}
        <a href={`${REPO}/releases`}>All releases</a>
      </footer>
    </div>
  );
}

export default App;

# Pania

A local-first trail recorder and viewer for Android (and desktop for development). Record hikes with GPS, import GPX/KML tracks, and browse them on a map with distance, duration and elevation stats. All data stays on the device.

Website: https://hypedmike.github.io/pania-track/

## Features

- **Record** a trail with GPS, including with the screen off (Android foreground service). Choose the sampling interval from 1 s to 60 s.
- **Trail tour**: press play on a trail's detail page and the app follows your position: where to go next (turns, next waypoint), distance left, estimated arrival time from your actual pace, and a progress bar. Optionally set a time to arrive by. Warnings appear for being late, arriving after sunset (computed on the device), thunderstorms, rain, snow, strong wind, heat, frost and lost GPS. Leaving the trail by more than a chosen distance (25–200 m, default 50 m) sends a notification, also with the screen off on Android. Weather comes from [Open-Meteo](https://open-meteo.com) (the only data sent is the coordinates of the middle of the remaining trail, no key or account). A tour and a recording cannot run at the same time.
- **Live stats outside the app**: while recording or following a tour, a persistent notification shows distance, climb and elapsed time (or distance left, arrival and progress for a tour), also on the lock screen. On Android 16 it asks to be promoted to a Live Update. A home screen widget shows the same numbers; it also declares the lock screen category, which only devices that allow lock screen widgets (some tablets) will honour. The numbers are computed by the native service, so they keep updating with the screen off.
- **Trail analysis** (the calculations are in Rust, `src-tauri/src/analysis`): moving and stopped time with the stops placed on the map (and addable as waypoints), your own speed against slope, climbs and descents with vertical speed and the steepest kilometer, fatigue (first against last third, corrected for slope), GPS quality with a one-tap clean-up (spikes removed, altitude smoothed, optionally replaced by terrain data from Open-Meteo), other trails on the same route with your best time, and an animated replay synced to the elevation profile.
- **Insights**: a heatmap of everywhere you have been, when you go out (hour, weekday, month) and, if you look it up, how temperature and rain change your pace (weather history from Open-Meteo, only coordinates and dates are sent).
- **Tour review**: each tour is saved, and afterwards compared with the plan kilometer by kilometer, showing where time was lost or gained. The plan, and the arrival time shown during the tour, come from your own pace model once you have recorded enough, and from a constant speed before that.
- **Import** tracks and waypoints from GPX and KML files (including Google Earth `gx:Track`).
- **Export / share** any trail as GPX.
- **Browse** trails filtered by source (recorded / imported), with a map preview per trail.
- **Trail detail** with an OpenStreetMap-based map, elevation profile, and stat tiles (distance, duration, elevation).
- **Share** a trail publicly over [Nostr](https://nostr.com) (after a confirmation): the track is simplified in Rust, signed with your profile key and sent to relays. Distance, climb and difficulty of what others share are always recomputed locally, never trusted.
- **Explore** trails other people shared near you on a map, filtered by distance, length, difficulty and on foot / by bike, and **bookmark** them to your device. A bookmarked trail keeps its creator's name and public key.
- **Profile**: a Nostr key pair created on the phone is your identity (the secret key stays in the Rust backend, encrypted with the Android Keystore).
- **Settings** for theme (system / light / dark) and recording interval.

## Tech stack

| Layer | Choice |
| --- | --- |
| Shell | [Tauri 2](https://tauri.app) (Rust) |
| UI | React 19, TypeScript, Vite, Tailwind CSS 4 |
| Routing / state | React Router, Zustand (settings persisted to `localStorage`) |
| Maps | Leaflet / react-leaflet, OpenStreetMap tiles |
| Storage | SQLite via `tauri-plugin-sql` |
| Native | Custom `trail-recorder` Tauri plugin (Kotlin), `tauri-plugin-geolocation` |

## Project structure

```
src/
  lib/                    Feature modules (views, components, stores, repositories)
    home/                 Trail list
    settings/             Theme, recording interval, off-track alert distance
    tour/                 Trail tour: progress along the trail, arrival time, warnings, off-track alerts
    trail/                Recording, saving, importing, detail view, map, elevation
  shared/                 Cross-feature code
    database/             SQLite connection
    gps/                  GPS service, background recorder, GPX/KML parsing, stats
    weather/              Open-Meteo hourly forecast client
    router/               Routes and navigation hook
    settings/ theme/      Settings store and color scheme handling
src-tauri/
  src/                    Rust app entry point
  migrations/             SQLite schema (trails, trail_coordinates, trail_waypoints)
  plugins/trail-recorder/ Native plugin: Android foreground service that buffers GPS points and, during a tour, raises off-track notifications
  capabilities/           Tauri permission sets (desktop and mobile)
  gen/android/            Generated Android project
scripts/set-version.mjs   Syncs a version across package.json, Cargo.toml and tauri.conf.json
```

### Data model

- `trails`: id, name, description, `source` (`recorded` | `imported`), timestamps.
- `trail_coordinates`: ordered points (lat, lon, altitude, timestamp) per trail.
- `trail_waypoints`: ordered named points of interest per trail.

Coordinates and waypoints are deleted with their trail (`ON DELETE CASCADE`).

### Routes

| Path | View |
| --- | --- |
| `/` | Home: trail list |
| `/record` | Live recording |
| `/record/save` | Name and save a recording |
| `/import` | Import a GPX/KML file |
| `/trails/:id` | Trail detail |
| `/settings` | Settings |
| `/settings/nostr` | Relays (defaults plus your own) |
| `/explore` | Map and list of shared trails nearby |
| `/explore/:eventId` | A shared trail, with the Bookmark button |
| `/profile` | Profile (create, back up the key, remove) |

## Getting started

### Prerequisites

- [Node.js](https://nodejs.org) 22 and [pnpm](https://pnpm.io) 10
- [Rust](https://rustup.rs) (stable)
- For Android: JDK 17, Android SDK (platform 37, build-tools 36.0.0) and NDK 28.2.13676358, plus the Rust Android targets. See the [Tauri prerequisites](https://tauri.app/start/prerequisites/).

### Develop

```sh
pnpm install
pnpm tauri dev              # desktop
pnpm tauri android dev      # Android device or emulator
```

Background recording is Android-only; on other platforms the app polls the position directly.

### Build

```sh
pnpm build                  # type-check and build the frontend
pnpm tauri build            # desktop bundle
pnpm tauri android build --apk
```

## CI and releases

- **CI** (`.github/workflows/ci.yml`): installs dependencies and runs `pnpm build` on pushes to `main` and on pull requests.
- **Release** (`.github/workflows/release-android.yml`): pushing a tag like `v0.2.0` builds a signed APK (arm64 and armv7) and publishes it as a GitHub Release. The tag is the single source of truth for the version: `scripts/set-version.mjs` writes it into every manifest and Android's `versionCode` is derived as `major*1_000_000 + minor*1_000 + patch` (so minor and patch must be ≤ 999).

Required repository secrets for signing:

`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`

To cut a release:

```sh
git tag v0.2.0
git push origin v0.2.0
```

## Recommended IDE setup

[VS Code](https://code.visualstudio.com/) with the [Tauri](https://marketplace.visualstudio.com/items?itemName=tauri-apps.tauri-vscode) and [rust-analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer) extensions.

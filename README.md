# Pania

A local-first trail recorder and viewer for Android (and desktop for development). Record hikes with GPS, import GPX/KML tracks, and browse them on a map with distance, duration and elevation stats. All data stays on the device.

## Features

- **Record** a trail with GPS, including with the screen off (Android foreground service). Choose the sampling interval from 1 s to 60 s.
- **Import** tracks and waypoints from GPX and KML files (including Google Earth `gx:Track`).
- **Export / share** any trail as GPX.
- **Browse** trails filtered by source (recorded / imported), with a map preview per trail.
- **Trail detail** with an OpenStreetMap-based map, elevation profile, and stat tiles (distance, duration, elevation).
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
    settings/             Theme and recording interval
    trail/                Recording, saving, importing, detail view, map, elevation
  shared/                 Cross-feature code
    database/             SQLite connection
    gps/                  GPS service, background recorder, GPX/KML parsing, stats
    router/               Routes and navigation hook
    settings/ theme/      Settings store and color scheme handling
src-tauri/
  src/                    Rust app entry point
  migrations/             SQLite schema (trails, trail_coordinates, trail_waypoints)
  plugins/trail-recorder/ Native plugin: Android foreground service that buffers GPS points
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

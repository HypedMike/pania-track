# Pania

A local-first trail recorder and viewer for Android. Record hikes with GPS, import GPX/KML tracks, and browse them on a map with distance, duration and elevation stats. All data stays on the device.

Website: https://hypedmike.github.io/pania-track/

The app is written in **Flutter**. Everything heavy that was already in Rust (track analysis, GPX, simplification, the Nostr identity and sharing, the update download) **stays in Rust** (`rust/`) and is imported into Dart with [flutter_rust_bridge](https://cjycode.com/flutter_rust_bridge/). The Android-only parts (the GPS foreground service, the Keystore, the installer) stay in Kotlin (`packages/pania_native`).

## Features

- **Record** a trail with GPS, including with the screen off (Android foreground service). Choose the sampling interval from 1 s to 60 s.
- **Trail tour**: press play on a trail's detail page and the app follows your position: where to go next (turns, next waypoint), distance left, estimated arrival time from your actual pace, and a progress bar. Optionally set a time to arrive by. Warnings appear for being late, arriving after sunset (computed on the device), thunderstorms, rain, snow, strong wind, heat, frost and lost GPS. Leaving the trail by more than a chosen distance (25–200 m, default 50 m) sends a notification, also with the screen off. Weather comes from [Open-Meteo](https://open-meteo.com) (the only data sent is the coordinates of the middle of the remaining trail, no key or account). A tour and a recording cannot run at the same time.
- **Live stats outside the app**: while recording or following a tour, a persistent notification shows distance, climb and elapsed time (or distance left, arrival and progress for a tour), also on the lock screen. On Android 16 it asks to be promoted to a Live Update. A home screen widget shows the same numbers. The numbers are computed by the native service, so they keep updating with the screen off.
- **Trail analysis** (the calculations are in Rust, `rust/src/analysis`): moving and stopped time with the stops placed on the map (and addable as waypoints), your own speed against slope, climbs and descents with vertical speed and the steepest kilometer, fatigue (first against last third, corrected for slope), GPS quality with a one-tap clean-up (spikes removed, altitude smoothed, optionally replaced by terrain data from Open-Meteo), other trails on the same route with your best time, and an animated replay synced to the elevation profile.
- **Insights**: a heatmap of everywhere you have been, when you go out (hour, weekday, month) and, if you look it up, how temperature and rain change your pace.
- **Tour review**: each tour is saved, and afterwards compared with the plan kilometer by kilometer, showing where time was lost or gained.
- **Plan** a route on the map: checkpoints, several route variants from [BRouter](https://brouter.de) with a steepness profile, CAI difficulty grade and hazards.
- **Import** tracks and waypoints from GPX and KML files (including Google Earth `gx:Track`). **Export / share** any trail as GPX.
- **Share** a trail publicly over [Nostr](https://nostr.com) (after a confirmation): the track is simplified in Rust, signed with your profile key and sent to relays. **Explore** trails other people shared near you, and **bookmark** them.
- **Profile**: a Nostr key pair created on the phone is your identity (the secret key stays in the Rust core, encrypted with the Android Keystore).
- **Settings** for theme, language (English, Italian), recording interval and off-track distance.

## Tech stack

| Layer | Choice |
| --- | --- |
| UI | Flutter (Material), Riverpod for state, go_router |
| Maps | flutter_map, OpenStreetMap tiles |
| Storage | SQLite (sqflite), shared_preferences for settings |
| Core logic | Rust crate `rust/` through flutter_rust_bridge 2 (generated bindings in `lib/core/rust`) |
| Native | Kotlin Flutter plugin `packages/pania_native` (foreground service, Keystore, installer) |

## Project structure

The Dart code is organised by feature. A feature has its `domain/` (plain Dart), `data/` (storage, network), `application/` (Riverpod controllers) and `presentation/` (screens, widgets) as far as it needs them.

```
lib/
  main.dart, app.dart        Start-up: Rust core, preferences, the app
  core/                      Cross-feature code
    rust/                    GENERATED bindings of the Rust core (do not edit)
    database/                SQLite connection and migrations (assets/migrations)
    gps/ weather/ routing/ geocoding/   GPS service, GPX/KML files, Open-Meteo, BRouter, Photon
    i18n/ theme/ settings/ router/ ui/  Language, colours, preferences, routes, shared widgets
  features/
    home/                    Trail list
    trail/                   Recording, saving, importing, detail, map
    tour/                    Following a trail: guidance, arrival time, warnings, review
    plan/                    Route planner
    analysis/                Per-trail analysis and Insights (Rust)
    stats/                   Totals, charts, records
    sharing/                 Explore and share over Nostr (Rust)
    profile/                 Nostr identity (Rust)
    settings/ update/        Settings, in-app updates (download in Rust)
rust/                        The Rust core (crate rust_lib_pania)
  src/analysis/ tracks/ identity/ sharing/ updater/ secrets/   The features, plain Rust, unit tested
  src/api/                   What Dart can call: one file per feature
packages/pania_native/       Android plugin in Kotlin (recorder service, Keystore, installer)
rust_builder/                cargokit glue that builds rust/ for Android
android/                     The Android app project
site/                        The landing page (GitHub Pages)
```

### How the Rust features reach Dart

`rust/src/api/*.rs` holds ordinary Rust functions. `flutter_rust_bridge_codegen generate` turns them into typed Dart functions and classes in `lib/core/rust`, so a feature just imports and awaits them:

```dart
import 'package:pania/core/rust/api/analysis.dart';
final analysis = await analyzeTrail(fixes: fixes, activity: Activity.foot);
```

Rust never calls Kotlin directly. The one place it needs Android, the secret key store, receives three callbacks from Dart at start-up (`api/core.rs`).

After changing anything in `rust/src/api` (or a type it uses), regenerate the bindings and commit the result; CI fails if they are out of date:

```sh
flutter_rust_bridge_codegen generate
```

### Data model

SQLite file `pania.db` in the app's private files folder (the same place and schema as the earlier Tauri version, so an update keeps your trails):

- `trails`: id, name, description, `source` (`recorded` | `imported` | `planned` | `bookmarked`), `activity`, author and sharing columns, timestamps.
- `trail_coordinates` / `trail_waypoints`: ordered points per trail. Deleted with their trail.
- `tour_runs` / `tour_run_fixes`: the tours that were followed, for the review.

Migrations are the numbered files in `assets/migrations`; append new ones, never edit one that has shipped.

### Routes

| Path | Screen |
| --- | --- |
| `/` `/explore` `/stats` `/profile` | The four tabs |
| `/record`, `/record/save` | Live recording, naming and saving it |
| `/import` | Import a GPX/KML file |
| `/plan`, `/plan/routes` | Route planner, comparing the variants |
| `/trails/:id`, `/trails/:id/tour`, `/trails/:id/analysis` | Trail detail, tour, analysis |
| `/tours/:id` | Review of a followed tour |
| `/insights` | Heatmap and patterns |
| `/explore/:eventId` | A shared trail, with the Bookmark button |
| `/profile/create`, `/profile/import` | Create or import the Nostr identity |
| `/settings`, `/settings/nostr` | Settings, relays |

## Getting started

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) (stable) and the Android SDK
- [Rust](https://rustup.rs) (stable) with the Android targets: `rustup target add aarch64-linux-android armv7-linux-androideabi`
- [flutter_rust_bridge_codegen](https://cjycode.com/flutter_rust_bridge/) 2.13.0 to regenerate bindings: `cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked`
- JDK 17

### Develop

```sh
flutter pub get
flutter run                          # an Android device or emulator
```

Gradle builds the Rust core for the phone's architecture (cargokit). Background recording is Android-only; elsewhere the app polls the position directly.

### Test

```sh
cargo test --manifest-path rust/Cargo.toml     # the Rust core
cargo build --manifest-path rust/Cargo.toml    # so the bridge test can load the library
flutter analyze
flutter test                                   # includes calls into the real Rust core
```

Pure logic of the Android service has JVM tests in `packages/pania_native/android/jvm-tests` (`gradle test`).

### Build

```sh
flutter build apk --release --target-platform android-arm64,android-arm \
  --dart-define=LATEST_RELEASE_URL=https://api.github.com/repos/HypedMike/pania-track/releases/latest
```

`LATEST_RELEASE_URL` is where the app looks for a newer version; leave it empty to turn the check off (the default points at this repository's releases).

## CI and releases

- **CI** (`.github/workflows/ci.yml`): Rust tests, Flutter analyze and tests, a check that the generated bindings are current, the Kotlin JVM tests and the site build.
- **Release** (`.github/workflows/release-android.yml`): every push to `main` bumps the minor version, builds a signed APK (arm64 and armv7) and publishes it as a GitHub Release; pushing a tag like `v2.0.0` uses that exact version. `versionCode` is `major*1_000_000 + minor*1_000 + patch` (minor and patch must be ≤ 999).

Required repository secrets for signing: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. For a local signed build put the same values in `android/keystore.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`). The same key must be used for every release, otherwise Android refuses to update the installed app.

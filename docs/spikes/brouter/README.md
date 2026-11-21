# Spike: offline route planning with BRouter

**Question:** can [BRouter](https://github.com/abrensch/brouter) (MIT) run as an embedded library and give
route options that differ by steepness?

**Verdict:** embedding works, so this is a **go**. The steepness options **partly work**. BRouter's elevation
cost cuts *total climb*, but it does not reliably avoid *steep sections*. That part needs work in the app (see below).

## What was done

- BRouter `ff7b616` (master, 2026-11-18). The Gradle build can't run in the cloud sandbox because it
  needs `dl.google.com` for the Android plugin. So the routing modules (`util`, `codec`, `expressions`,
  `mapaccess`, `core`, `map-creator`) were compiled with plain `javac`. The only external dependencies are
  `osmosis-osm-binary` and `protobuf-java`, and only the map creator uses them.
- The test data comes from BRouter's own repository: a real OSM extract of Dreieich, near Frankfurt
  (about 2.5 × 1.8 km), plus SRTM elevation (148–201 m).
- Routing tiles (`.rd5`) were built with the same pipeline as BRouter's `MapcreatorTest`.
- Three start/end pairs were routed with `hiking-mountain.brf` in three variants. The variants differ only
  in values overridden per request through `RoutingContext.keyValues`:

  | variant  | consider_elevation | uphill / downhill cost | cutoff |
  |----------|--------------------|------------------------|--------|
  | direct   | 0                  | (ignored)              | –      |
  | balanced | 1                  | 7 / 7 (profile default)| 3 %    |
  | gentle   | 1                  | 40 / 30                | 1 %    |

- The real terrain has only about 50 m of relief. To mimic mountain grades on the same real path network,
  a second set of tiles was built with height differences multiplied by 10 ("x10").

The harness is [`Spike.java`](Spike.java). It has three commands: `exaggerate`, `build` and `route`.

## Results

Grades are measured over windows of at least 50 m, after a 5-point median filter. `ms` is the routing
time on a desktop JVM.

```
### real terrain (~50 m relief)
route  variant     dist_m  gain_m   maxUp%  maxDown%   ms
0      direct        2789      12      3.8      20.7  101
0      balanced      2646      14      3.8      20.7   24
0      gentle        2646      14      3.8      20.7   16
1      direct        2663      23      4.0       2.7   15
1      balanced      2663      23      4.0       2.7   14
1      gentle        3136      23      5.5       3.7   21
2      direct        2127      19      7.1       5.8   11
2      balanced      2127      19      7.1       5.8    9
2      gentle        2127      19      7.1       5.8    9

### x10 relief (synthetic, same paths)
0      direct        2788     217     37.5      65.9   79
0      balanced      2789     217     37.5      47.2   24
0      gentle        2902     201     37.5      47.2   18
1      direct        2663     261     38.8      24.1   15
1      balanced      2693     251     38.8      26.1   18
1      gentle        2648     273     52.9      35.5   17
2      direct        2127     277     71.1      55.2   16
2      balanced      2329     192     70.8      36.6   15
2      gentle        2329     192     70.8      36.6   14
```

## Findings

1. **It can be embedded.** The routing modules have no Android, AWT or Swing imports. The compiled classes
   come to about 1 MB, including the map creator, which the app wouldn't ship. The API is
   `new RoutingEngine(null, null, segmentDir, waypoints, ctx).doRun(0)` followed by `getFoundTrack().nodes`,
   which gives lon/lat/elevation for every point. A Kotlin Tauri plugin can call this directly.
2. **Elevation is in the data.** Every track point carries an SRTM elevation, which is enough for
   `computeStats` and the elevation profile.
3. **Elevation-aware variants cut total climb.** On x10 route 2, total climb drops from 277 m to 192 m
   (−31%) for about 10% more distance.
4. **They don't put a limit on maximum grade.** `balanced` and `gentle` usually return the same route, and on
   x10 route 1 `gentle` is even steeper at its worst point. BRouter's cost model (`StdPath`, the
   `elevationpenaltybuffer` logic) penalises *accumulated* climb above a cutoff, not individual steep
   sections. Planned fix: generate several candidates (profiles × `alternativeidx`), measure the max grade of
   each in the app, and present them as easy / moderate / steep. Possibly add a custom profile as well.
5. **The elevation at start and end points can be wrong.** In one case the snapped end point got 128 m,
   below anything in the terrain data. The app must smooth elevation, for example with a median filter,
   before computing grades.
6. **Profile overrides must be numbers.** `"true"` fails to parse; use `1` / `0`.

## Not yet proven

- Performance on a phone with a real Alpine tile and routes of 10–20 km. On this tiny area, a route takes
  10–100 ms on a desktop.
- The size of real Europe `.rd5` tiles. brouter.de was not reachable from the sandbox.
- Real mountain terrain. The x10 data is synthetic, and the test area has no `sac_scale` tags.
- Android packaging: whether the modules build for Android API level / D8 and how memory use looks.

## Suggested next step

Run the same harness on a real Alpine tile, for example `E10_N45.rd5` from https://brouter.de/brouter/segments4/,
with real long routes. Then prototype the Kotlin plugin on a device.

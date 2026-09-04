# v90.32 — Route Guidance reroute correctness + CarPlay-assisted speed-limit matching

v90.32 keeps the v90.31 adapter-only navigation architecture and U2W v8.5 live exporter. It is a HUD-app-only update; no new U2W firmware is required.

## 1. Restore original maneuver text

The OCR-era diagnostic suffix is removed from the physical HUD maneuver text. The native HUD maneuver packet already carries the current distance as an Int32 meter field, so the first line returns to the original presentation:

```text
Turn right
N 34th St
```

instead of:

```text
Turn right • 0.2 mi
N 34th St
```

`displayDistanceText` is retained in logs/diagnostics but is no longer duplicated in the maneuver text.

## 2. Correct CarPlay current-maneuver semantics

The v90.31 client treated the second exported maneuver index as `nextManeuverIndex` and deliberately preferred it. The September 3 field drive demonstrated that the two values behave as a current-maneuver list: for the N 33rd Street case the first index resolved to `Turn left -> Mantua Ave`, while the second resolved to the subsequent `Turn right -> N 34th St` maneuver.

v90.32 therefore:

- uses the **first valid current maneuver index** as the primary HUD instruction;
- treats `0xFFFF` as a sentinel/no-index value;
- never falls back to `maneuvers.first` when the referenced maneuver is absent;
- holds the last valid instruction through short 0x5201/0x5202 synchronization gaps.

The U2W v8.5 JSON field names remain backward-compatible (`currentManeuverIndex` and `nextManeuverIndex`), but the app interprets the first value as primary/current and does not promote the second value to the HUD.

## 3. Reroute stabilization

The physical September 3 capture showed Google's actual recalculation transition as `5 -> 0 -> 3 -> 1`: state 5 is explicit rerouting, state 0 appears briefly during route teardown/rebuild, state 3 is calculating, then state 1 resumes active guidance. v90.32 arms a three-second same-source reroute grace only after state 5 so that the transient state 0 does not incorrectly return the HUD to Freeride. A normal state 0 with no preceding state 5 still exits Navigation immediately. While the transition is active, the HUD keeps the last valid maneuver instead of accepting a potentially mismatched old/new route table. Once a stable active state returns, the first current-maneuver candidate must remain semantically stable across two progressive Route Guidance sequence values before it replaces the held maneuver.

This prevents both observed failure modes:

- displaying the second/future maneuver from the new route;
- falling back to maneuver index 0 from an old route when an index is temporarily `0xFFFF` or its 0x5202 record has not arrived yet.

New `CARPLAY RGD REROUTE` and expanded `CARPLAY RGD HUD` logs include route state and both exported indexes for future field validation.

## 4. CarPlay-assisted speed-limit road matching

Route Guidance does **not** become a speed-limit source. Posted speeds still come only from the existing OSM explicit tags / same-road consensus and Philadelphia Street Centerline GIS data.

When the selected speed source is `Improved + Philly GIS`, fresh CarPlay Route Guidance supplies semantic road context:

- source application;
- current road;
- road after the current maneuver;
- distance to maneuver;
- route state / rerouting state.

The current road gives a weighted score bonus to geometrically plausible OSM/GIS road candidates. It is not a hard filter, so GPS trace, distance and course still have to support the candidate. During route calculation/rerouting states 3/5 this current-road bonus is reduced from `-1.25` to `-0.15` so transitional route semantics cannot pin the matcher to a stale road.

Road names are normalized across common provider/OSM differences, including examples such as:

- `N 33rd St` <-> `North 33rd Street`
- `Martin Luther King Jr Dr` <-> `Martin Luther King Junior Drive`

The upcoming road is used only as a completed-turn tie-breaker. It cannot pull the matcher onto the next street while approaching the intersection: the candidate must already be within 20 m, aligned within 25 degrees of the current GPS course, and the maneuver must be within 180 m. This same conservative tie-break applies to OSM completed-turn takeover and Philadelphia GIS current-geometry selection.

If Route Guidance is unavailable/stale, or Navigation is inactive, the existing GPS/map matcher runs unchanged.

## Waze

No Waze-specific change is included. Waze remains third in the existing priority order `Google Maps > Apple Maps > Waze`. The stationary end-of-drive test exposed a Waze source but no active route state; a normal driving test can determine whether Waze begins supplying active Route Guidance once the vehicle progresses onto the route.

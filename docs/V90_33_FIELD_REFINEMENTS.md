# v90.33 — September 4 field refinements

v90.33 is based on v90.32.1 and requires no U2W firmware update. Keep the existing U2W v8.5 live exporter installed.

## Apple Maps pre-road/start-route state

The September 4 morning capture ended with a valid Apple Maps live state containing `routeState=6`, `active=true`, destination `Work`, and maneuver 0 `Start on River Ridge Ct`. During this initial phase Apple Maps can leave the same Route Guidance sequence unchanged for much longer than the ordinary active-route cadence. The field log demonstrated gaps near 15 seconds and the former 4.5-second sequence freshness rule repeatedly released CarPlay ownership, producing Navigation/Freeride flicker.

v90.33 uses state-aware freshness:

- active state 6: 20-second sequence-progress window;
- normal active route: unchanged 4.5-second window;
- reroute state 5 and observed 5→0→3→1 grace: unchanged;
- ordinary state 0: immediate Navigation OFF/Freeride.

Sequence progression timestamps are retained independently from the currently cached candidate, so a repeatedly served stale JSON snapshot cannot reset its own freshness simply by being reinserted after pruning.

## Route Guidance-assisted speed matching

CarPlay semantic matching remains limited to Improved + Philly. It never supplies or invents the posted speed value.

The current-road score adjustment now requires compatible geometry:

- moving, <=40 m and <=45 degrees: full semantic bonus;
- moving, <=50 m and <=70 degrees: reduced semantic bonus;
- more contradictory geometry: no bonus;
- below 2 m/s: distance-only gating because CLLocation course is unreliable.

States 3, 5 and 6 receive only the weakened transition bonus. OSM/GIS matcher logs include `rgdCurrent=<raw CarPlay road>` for direct field comparison. A Philadelphia-specific normalization also treats Apple `Martin Luther King Dr` as the same road identity as OSM `Martin Luther King Junior Drive`.

## Overspeed ambient warning

The previous single warning brightness becomes the Day warning brightness and keeps its persisted value. A new Night warning brightness defaults to 20%. The mode is selected from the existing confirmed Center/headlight state.

When the warning finishes, the selected warning light no longer jumps directly from warning RGB to the preferred RGB. v90.33 performs a one-second smoothstep transition of both RGB and brightness. RGB/brightness writes alternate at 50 ms cadence to respect BLE write-without-response backpressure, followed by an exact final preferred RGB + steady brightness commit.

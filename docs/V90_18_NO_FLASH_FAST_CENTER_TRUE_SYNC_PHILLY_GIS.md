# v90.18 — BLEDIM no-flash Breath, fast Center day/night, true sync cohort, Improved + Philly GIS

v90.18 keeps the reliable v90.17 per-controller power-on lifecycle and makes four focused changes based on the 2026-08-29 three-trip field log and visual test.

## Ambient: BLEDIM no-flash normal path

Door and Dashboard use BLEDIM2. Their Power ON command can visibly expose the controller's remembered/high brightness before a following brightness packet arrives. The v90.17.1 terminal safety commit therefore produced a visible blink even after an otherwise smooth Breath.

v90.18 keeps Power ON recovery available when a real write fails, but removes it from successful routine completion:

- fresh BLEDIM GATT control still waits 1.5 s for firmware boot;
- preparation preloads normal RGB and the resolved steady baseline;
- Power ON is sent once, followed immediately by a baseline-brightness reassert;
- Breath uses the existing v90.10-derived 20 Hz/raw-255 brightness path;
- successful terminal commit is **brightness only**;
- if that final brightness cannot be delivered, the existing one-shot fail-safe may still use Power ON -> RGB -> steady brightness.

Lotus/Center keeps its proven protocol path unchanged.

## Fast day/night owner

Animation remains independent from engine state and day/night state.

Day/night now returns to the older responsive Center/BLEDOM signal:

- Center present -> Night -> HUD Auto Brightness ON + Door night target;
- Center absent -> Day -> HUD Auto Brightness OFF + Door day target.

Dashboard+Center BOTH-ON/BOTH-OFF is retained only as a stabilized flight-recorder cross-check. Dashboard cannot delay the HUD or Door response.

Automatic Door day/night changes use a dedicated 1.0-second fade. The user-adjustable manual/group brightness transition duration remains separate.

## True optional synchronization

Sync OFF remains independent per-light behavior.

Sync ON now groups **power-on events**, not merely devices that happen to finish preparation at similar times:

1. first eligible controller opens a 3.0-second discovery cohort;
2. later controllers that appear during that cohort are expected participants;
3. after discovery closes, the coordinator allows up to 1.5 seconds for expected members to finish their protocol-specific preparation;
4. all prepared members receive one common Breath T0;
5. an expected member that still misses the bounded grace gets a complete independent Breath later rather than joining mid-waveform.

Manual Preview pre-registers all enabled/controllable lights into the same cohort before preparation so Preview can exercise the same common-T0 path.

## Speed-limit source cleanup

The UI now exposes exactly three speed-limit modes:

1. **Current** — original decompiled HUDWAY matcher.
2. **OSM Trace** — the v90.17 field-tested rolling trace matcher using explicit OSM speed tags. It is intentionally retained as an A/B baseline.
3. **Improved + Philly GIS** — new all-road rolling trace plus optional Philadelphia public speed-limit data.

Existing installs that had the removed `Enhanced OSM` mode selected migrate to `OSM Trace`.

## Improved OSM Trace

The improved mode queries all nearby drivable OSM highway geometries, including roads without an explicit `maxspeed`. This allows the matcher to recognize that the vehicle has left an arterial/expressway and entered a neighborhood road instead of continuing to borrow a nearby tagged road's speed.

An untagged OSM road does **not** automatically invent a speed limit. If no fresh explicit or official value is available, the last sign gets a 4-second continuity grace and is then cleared from the HUD.

The generic trace scorer also fixes the old `Double.greatestFiniteMagnitude` sentinel bug: a trace sample that matches no segment is now counted as unmatched rather than as an astronomical but technically finite score.

## Philadelphia public GIS fusion

Inside a loose Philadelphia-area envelope, Improved mode also queries the City of Philadelphia public ArcGIS `SpeedLimits` FeatureServer:

- Layer 0: Street Speed Limits;
- Layer 1: Residential Streets.

The parser accepts the service's speed fields (`SPEED_LIMITS`, `SpeedLimits_MPH`, `SPLIMIT`). Residential-layer geometry without a valid explicit value uses 25 mph as the local residential fallback. The City result must still geometrically agree with the rolling GPS trace before it can be accepted.

A confidently matched OSM `motorway`/`motorway_link` with an explicit limit is protected from a nearby surface-street GIS override. This is specifically intended to preserve a true Roosevelt Expressway 50-mph match while allowing City data to correct the field-observed false 50-mph `trunk`/Boulevard overlap.

If the Philadelphia service is unavailable, Improved mode continues with improved OSM only. No commercial map API or key is introduced.

## Flight recorder

New/updated diagnostics include:

- `AMBIENT ...` Center-driven day/night and sync-cohort lifecycle;
- `IMPROVED TRACE GPS`;
- `IMPROVED TRACE PATH`;
- `IMPROVED TRACE OSM MATCH`, including geometry and explicit speed tags;
- `PHILLY GIS QUERY`;
- `PHILLY GIS MATCH`, including matched segment endpoints;
- `IMPROVED TRACE DECISION`;
- `IMPROVED TRACE OUTPUT` with freshness/source/margin.

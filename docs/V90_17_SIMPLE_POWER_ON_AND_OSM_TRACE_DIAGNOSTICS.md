# v90.17 — Simple per-light power-on architecture + OSM Trace diagnostics

## Design goal

v90.17 removes the engine/courtesy/startup choreography from ambient-light animation.
The app no longer tries to infer *why* a controller received vehicle power before it is
allowed to animate. Each controller owns a small, independent lifecycle:

`BLE return -> GATT ready -> (BLEDIM boot settle) -> Power ON -> RGB -> Breath -> steady target`

A physical/GATT disconnect immediately re-arms that controller. Its next return is a
brand-new power-on event and gets a complete Breath again.

Engine/HUD/OBD state is retained for diagnostics and unrelated vehicle features, but it
cannot suppress, cancel, admit, or replay an ambient-light Breath.

## Per-light behavior

### BLEDIM Door / Dashboard

1. New CoreBluetooth connection clears the current connection-session animation flag.
2. FFF1 GATT control becomes ready.
3. Wait 1.5 seconds for the BK-BLE firmware to settle after fresh vehicle power.
4. Reliably send `Power ON`.
5. Reliably send the configured normal RGB color.
6. Reliably establish the current steady baseline brightness.
7. Run the v90.10-derived 20 Hz/raw-255 Breath.
8. End with a semantic terminal commit:
   `Power ON -> normal RGB -> final steady brightness`.

If physical power disappears at any point, the current operation is abandoned. The next
BLE return starts again from step 1. No animation epoch survives a disconnect.

The existing one-shot animation-abort fail-safe remains for an in-place cancellation
while the controller is still writable. There is no v90.13 repeated/three-round recovery
loop.

### Lotus Lantern Center

Center does not need the BLEDIM boot delay. Once its FFF3 control characteristic is
ready, it enters the same Power/RGB/Breath/final-steady lifecycle immediately.

## Optional synchronization

`Synchronize nearby power-on Breaths` is a persisted runtime setting and defaults OFF.

- **OFF:** each controller begins its complete Breath as soon as its own preparation is
  finished. No controller waits for another controller.
- **ON:** prepared controllers are grouped for up to 2.5 seconds and then share one
  timeline. The 2.5-second window is long enough to include a BLEDIM controller that
  first waits through its 1.5-second firmware-settle interval.
- A controller that becomes ready after the sync window closes does **not** join a Breath
  halfway through. It receives its own complete independent Breath.

This makes synchronized vs. independent behavior directly testable without changing the
underlying BLE transport.

## Door day/night brightness is separate from animation

Dashboard + Center are only a day/night signal:

- both ON and stable for 0.75 seconds -> Night / headlights ON;
- both OFF and stable for 0.75 seconds -> Day / headlights OFF;
- mixed -> hold the last confirmed state.

This signal does **not** trigger a Breath. It only controls:

- Door's steady day/night target brightness; and
- HUD Auto Brightness when that feature is enabled.

If Door is already in its power-on Breath when day/night changes, only the Breath's final
return target is updated. If Door is in the BLEDIM boot/preparation phase, the upcoming
Breath reads the latest target. Otherwise Door performs one smooth brightness fade.

Door fades are event-driven. The 0.5-second background watchdog does not reapply Door
brightness, and an active fade records its target so a duplicate event cannot cancel and
restart the same transition.

## Ambient flight recorder

`AMBIENT TRACE` is event-driven rather than frame-driven. A snapshot includes:

- diagnostic HUD/OBD engine witnesses;
- raw + confirmed Dashboard/Center day/night state;
- synchronization mode and active/queued Breath counts;
- Door, Dashboard and Center connection state;
- GATT readiness;
- logical recent-power evidence;
- runtime and preferred brightness;
- active owner (`bootSettle`, `prep`, `breath`, `fade`, `restore`, `failsafe`, `warning`).

Additional lifecycle records identify boot settling, Breath preparation, independent or
synchronized start, cancellation, final steady commit, and fail-safe restoration.

## OSM Trace flight-recorder diagnostics

When **OSM Trace** is selected, the log now records enough information to investigate a
wrong speed-limit sign after the drive:

- `OSM TRACE GPS`: exact current latitude/longitude, horizontal accuracy, course, speed,
  and trace-buffer size.
- `OSM TRACE PATH`: the exact rolling GPS samples used by the matcher, including
  latitude/longitude/course/accuracy.
- `OSM TRACE QUERY`: Overpass query center, radius and returned road count.
- `OSM TRACE MATCH`: current/pending way plus the top candidate roads. Each candidate
  includes OSM way ID, name/ref/highway, resolved limit, trace score, current-point
  distance, bearing error, matched trace-point count, travel direction, the exact closest
  OSM segment endpoints, and base/forward/backward speed tags.
- `OSM TRACE DECISION`: retain, create pending switch, confirm switch, or reject switch,
  including confidence margin.
- `OSM TRACE OUTPUT`: exact GPS point, final resolved/held limit, accepted way, pending
  way and confidence margin.

These records are diagnostic only; v90.17 does not change the current OSM Trace scoring
algorithm. The logs now contain precise location history while OSM Trace is active, so
share/export them with that privacy implication in mind.

## Transport intentionally unchanged

The field-proven v90.10-derived packet/animation transport remains the baseline:

- BLEDIM2 FFF1 `55 AA` packets;
- per-controller sequence counters;
- 20 Hz visual clock with native raw 0–255 BLEDIM brightness;
- Lotus FFF3 `7E ... EF` packets;
- write-without-response backpressure handling;
- reliable semantic Power/RGB/baseline/final-brightness writes.

v90.13's BLEDIM 10 Hz experiment, minimal-GATT experiment and repeated three-round
steady-state recovery are not restored.


## v90.17.1 audit notes

The pre-drive audit preserves the v90.17 architecture and adds four safety/diagnostic
corrections: failed terminal Breath commits arm the existing one-shot restore fail-safe;
shared fade cancellation cleans every member of the cancelled operation; OSM Trace marks
held prior signs as `fresh=0` so they do not refresh warning eligibility; and engine
diagnostics no longer treat retained Door accessory power as proof that the engine is on.
The BLEDIM2 packet builder and 20 Hz/raw-255 animation transport are unchanged.

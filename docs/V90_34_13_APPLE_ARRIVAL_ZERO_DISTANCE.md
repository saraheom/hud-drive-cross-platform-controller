# v90.34.13 — Apple Maps arrival zero-distance preservation

## Field evidence

The September 7 Apple Maps drive exposed a source-valid zero that the iOS compatibility fallback misclassified as missing.

At the destination, U2W v8.8 exported:

```text
source=Apple Maps
routeState=2
destination=Target
timeRemainingSeconds=0
distanceRemainingMeters=0
distanceRemainingText=0
distanceToManeuverMeters=0
distanceToManeuverText=0
```

Apple Maps' maneuver table simultaneously retained a blank destination placeholder:

```text
index=12
description=""
type=12
afterRoad=""
distanceMeters=1931
displayDistanceText=1.2
```

The v90.34.12.1 resolver used:

```swift
snapshot.distanceToManeuverMeters > 0
    ? snapshot.distanceToManeuverMeters
    : maneuver.distanceMeters
```

so the explicit live zero selected the stale `1931` table distance. The physical HUD log confirmed that the iPhone then transmitted `0x0000078B` (1931) in the native maneuver packet, producing the observed 1.2-mile destination display.

## v90.34.13 resolver rule

`resolvedManeuverDistanceMeters(snapshot:maneuver:)` now applies this precedence:

1. If Route Guidance explicitly reports arrival (`routeState == 2`, remaining distance `0`, remaining time `0`), send `0 m`.
2. Otherwise, if the live maneuver distance is positive, use it.
3. Otherwise, if the live display-distance text is nonempty, treat the numeric zero as explicit and use `0 m`.
4. Only when the live numeric distance is zero **and** the display-distance text is empty does the legacy maneuver-table fallback remain eligible.

This deliberately retains the old compatibility fallback for older/transitional U2W snapshots while preventing explicit CarPlay zeros from being replaced by stale table data.

## Blank destination placeholder

Apple Maps may advance from an actual final maneuver such as `Arrive at Target` to a blank destination placeholder. When `afterRoad` and `description` are both empty and the mapped maneuver is `.destination`, the HUD street line now uses `snapshot.destination` before falling back to `snapshot.currentRoad`.

Captured result:

```text
before: Destination, 1931m, Presidential Blvd
after:  Destination, 0m, Target
```

The optional **Show Current Turn Text** setting still independently controls the upper `Arrive at destination`/turn-action line.

## Scope boundary

No change is made to:

- U2W firmware/exporter v8.8;
- Apple/Google/Waze source priority;
- 0x5204 lane decoding or Near Turn/Persistent lane presentation;
- native HUD maneuver packet format;
- ETA packet handling;
- speed-limit continuity/matching;
- ambient-light behavior;
- dashboard widgets;
- Scale/Perspective controls;
- firmware maintenance / boot animation.

The fix is app-side Route Guidance normalization only.

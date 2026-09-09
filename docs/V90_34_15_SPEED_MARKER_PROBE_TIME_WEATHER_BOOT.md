# v90.34.15 — temporary speed-marker protocol probe + time/weather boot-state fix

v90.34.15 is based on v90.34.14. The production GPS/OSM speed-limit matcher and its normal packet sequence are intentionally unchanged. This build adds a temporary Vehicle-screen A/B probe so the physical HUD can be tested against the exact automatic-warning sequence recovered from HUDWAY Drive 1.4.6.

## Temporary speed-marker probe

The decompiled original Automatic branch when `isInTravelMode=true` sends:

1. `HudSpeedLimitAndToleranceCommandPacket(limit=0, tolerance=0, style=0)`
2. `DisplaySpeedWarningCommandPacket(threshold=<posted/test limit>)`

The existing production path remains:

1. rectangular/square speed-limit state with the legal limit
2. `DisplaySpeedWarning` with the same confirmed legal limit

The Vehicle tab now contains **SPEED MARKER PROBE — TEMPORARY** with a 5–100 mph test threshold and four actions:

- **A — Exact original Automatic/TRAVEL sequence**: sends only the recovered original two-packet sequence.
- **B — Original sequence + restore square sign**: sends A, waits 350 ms, then re-sends the normal production square sign at the test limit. This tests whether any native marker initialized by the original sequence survives restoration of the visible sign.
- **C — Current production sequence**: sends the current v90.34.14-style legal-limit + warning sequence for direct A/B comparison.
- **Restore live speed-limit state**: returns the HUD to the current live matcher result or clears the sign/warning if no live limit exists.

The probe does not change speed-limit source selection, cached road identity, current resolved limit, warning confidence, persisted settings, or ambient overspeed logic.

A new diagnostic-only `HudCommands.speedLimitProbe(...)` permits style 0. The production `HudCommands.speedLimit(...)` remains hard-coded to style 1.

## Time/weather fresh-boot issue

The September 9 field log showed the persisted value was correctly `false` and the app did transmit `Time/weather false` during both phase-2 and phase-3 HUD rehydration. However, in v90.34.14 those OFF packets were queued **before** the Freeride/Navigation dashboard-profile packets. The physical firmware can reconstruct the dashboard after that point and restore its bottom-panel boot default, leaving time/weather visible even though the iPhone setting remains OFF.

v90.34.15 changes ownership/order rather than changing the saved setting:

- phase 2 applies dashboard profiles/active mode first, then sends the persisted time/weather state;
- phase 3 does the same;
- `HudOBDController` notifies `AppState` whenever either Freeride or Navigation profile is applied;
- AppState performs one debounced 300 ms post-dashboard reassert using the **current** persisted `showTimeWeather` value;
- manual widget-profile changes and navigation profile reconstruction therefore also preserve the user's time/weather choice;
- the delayed task is cancelled on HUD disconnect.

No forced OFF behavior is introduced. Users who enable time/weather continue to receive `true`; users who disable it receive `false` after dashboard reconstruction.

## Unchanged

- CarPlay/U2W v8.8 Route Guidance and Now Playing
- Google/Apple/Waze source handling
- lane guidance and ETA
- Apple Maps zero-distance arrival fix
- production speed-limit matcher and warning-confidence policy
- ambient RGB brightness restoration from v90.34.14
- Scale/Perspective
- HUD firmware maintenance and boot-animation override

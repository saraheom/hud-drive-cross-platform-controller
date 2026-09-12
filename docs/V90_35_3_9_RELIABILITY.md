# v90.35.3.9 — MainVideo, Route Guidance and ambient-light recovery

This release pairs with **U2W v8.15** and keeps the proven v90.35.3.7 mode-6 start sequence and all v90.35.3.8 map-layout calibration controls.

## MainVideo map freeze

The September 12 car log showed the 800×480 MainVideo decoder progressing normally and then stopping while semantic Google Maps Route Guidance continued to update. Manually reconnecting the MainVideo endpoint resumed decoding. U2W v8.15 replaces the v8.11 BusyBox `tail -f` follower with a rotation-aware ARM streamer that detects the exporter's same-inode H.264 truncation and continues from the new generation on the same HTTP response.

The iOS client also has a backup freshness watchdog: while the HTTP stream is connected, 3 seconds without a decoded frame restarts only the MainVideo worker. A worker-generation token prevents late callbacks from the previous connection from overwriting the new connection's state.

## Route Guidance transient drop

Malformed/partial U2W JSON must no longer be interpreted as a route ending. While a previously selected CarPlay source has a valid active route, transport/JSON errors hold the last valid maneuver, ETA and lane state for up to 45 seconds. A real route end requires two consecutive successfully decoded inactive/state-0 snapshots before the app sends Navigation OFF.

U2W v8.15 also serializes the Route Guidance and media JSON publication paths so concurrent preload-hook threads cannot race through one shared scratch buffer/temp filename.

## HUD relay Stop -> Start

U2W relay state is now session-scoped. Start allocates a new session id and clears only that session's discovery/client/live-frame markers. Stop leaves the three healthy relay daemons and latest frame in place while the app returns the HUD to mode 4. This avoids the prior teardown/rebind race and prevents old log entries from being mistaken for a current HUD connection.

## Ambient-light recovery

The field log showed two independent stale-state cases:

- Center/BLEDOM could reconnect while the app still held a stale logical-present flag but `confirmed=day`; the old code only promoted NIGHT on a `becamePresent` edge, so Door remained at daytime brightness until a later advertisement.
- A known BLEDIM cold/off epoch could still enter `Already-On Minimal`, whose brightness-only preparation cannot physically wake a controller that is actually off.

v90.35.3.9 therefore lets any fresh positive Center evidence reassert NIGHT whenever the confirmed state is still DAY. It also tracks BLEDIM controllers that require a one-time explicit power prime. Dashboard headlight reconnects and manual OFF events mark that requirement; after the normal 1.5-second controller settle, the next Breath uses the proven Power ON -> RGB -> preferred-brightness preparation once, then returns to Already-On Minimal for normal warm operation.

## Intentionally unchanged

- OBD2-first speed remains deferred.
- Existing map crop/layout/boldness/position controls are unchanged.
- Route provider priority remains Google Maps > Apple Maps > Waze.
- No OCR or ScreenCaptureKit fallback is added.

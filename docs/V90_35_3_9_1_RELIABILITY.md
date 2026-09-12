# v90.35.3.9.1 — MapVideo / Route Guidance reliability + targeted Dashboard reconnect recovery

This app revision pairs with the unchanged **U2W v8.15** image. MainVideo rotation-safe streaming, the iOS 3-second decoded-frame freshness watchdog, the 45-second last-valid Route Guidance transport holdover, two-sample genuine route-end confirmation, and session-scoped HUD relay state are unchanged from v90.35.3.9.

## Ambient correction

The broad v90.35.3.9 ambient experiment was narrowed after reviewing the field behavior. Normal headlight power-up already physically powers the BLEDIM Dashboard controller, and the finalized production behavior deliberately avoided a software Power ON before Breath because it produced a visible blink. v90.35.3.9.1 therefore restores the prior Center/day-night state transition logic and does **not** arm an explicit Power ON merely because Center/headlight went OFF.

For a fresh Dashboard GATT reconnect after startup, if no active HUD-start/headlight cohort owns the device, the app now:

1. sends no immediate Power ON/RGB restore;
2. waits the existing 1.5-second BLEDIM boot-settle interval;
3. if a strict headlight cohort opened meanwhile, hands Dashboard to that synchronized Breath; otherwise
4. reasserts only the preferred Dashboard brightness.

This prevents an early write-without-response restore from racing a just-booted BLEDIM controller and also restores the desired steady brightness after an interrupted Breath that may have stopped near 0%.

A software Power ON/RGB/baseline prime remains available only after this app itself sent an explicit manual Power OFF. In that case logical LED output is known OFF, so the next manual ON/Preview must explicitly wake it once before returning to Already-On Minimal.

## Intentionally unchanged

- Center/day-night state machine from v90.35.3.8.
- Normal headlight OFF→ON Already-On Minimal behavior; no routine software Power ON.
- Door day/night brightness policy.
- Map crop/layout/boldness/position controls.
- Route provider priority Google Maps > Apple Maps > Waze.
- OBD2-first speed remains deferred.

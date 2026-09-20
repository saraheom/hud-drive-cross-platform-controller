# HUD Controller v90.35.3.24 + U2W v8.24

This release addresses the remaining MainVideo startup race seen in the 2026-09-19 parked test and the previously confirmed VideoToolbox continuity failure, while changing the ambient night→day transition back to Center/BLEDOM authority with a short guard.

## MainVideo startup: bounded recent-IDR bootstrap

U2W v8.23 waited only for an IDR that arrived *after* the iPhone connected. In the latest parked test, the first valid IDR arrived milliseconds before the TCP client, so the source continued producing P-frames but the client could never bootstrap.

U2W v8.24 keeps the dedicated TCP/15332 architecture and adds a bounded recent decoder anchor:

- wire magic `U2WH2643`;
- validated SPS/PPS + latest valid IDR + following valid slices;
- hard cap of 4 MiB;
- new client immediately receives that anchor when it is still bounded/valid;
- otherwise it waits for the next valid live IDR;
- no 17–20 MiB whole-GOP burst and no long-lived Boa video stream.

The iOS app starts MainVideo predecode shortly after app launch rather than waiting for HUD BLE and preserves that predecode when HUD BLE disconnects. This makes the normal car session much more likely to own the H.264 reference chain from its first valid IDR onward.

## Decoder continuity

The earlier successful parked test proved the relay could deliver real 800×480 frames, then VideoToolbox became invalid while TCP/H.264 remained healthy. v90.35.3.24 therefore:

- prefers software VideoToolbox decode (`EnableHardwareAcceleratedVideoDecoder = false`) for the 800×480 navigation stream;
- does not proactively destroy the decoder on app lifecycle transitions;
- retains the v90.35.3.23 fatal `-12903` and stale-output recovery diagnostics;
- on a true hard decoder recovery, reconnects TCP so v8.24 can replay the bounded recent anchor if it is still available.

The 20-second parked continuity preflight remains required before driving.

## Ambient day/night

Center/BLEDOM again owns fast day/night state:

- Center evidence present → NIGHT immediately;
- Center transport/presence loss while NIGHT is active → preserve NIGHT for 1.0 second;
- advertisement/reconnect during that guard cancels DAY;
- Center still absent after the guard → DAY without waiting for Dashboard;
- HUD Auto Brightness turns off and the Door brightness fade begins immediately after DAY commit;
- Dashboard remains a diagnostic cross-check and no longer gates the transition.

With the existing 1-second brightness fade, the intended visible NIGHT→DAY response is roughly 1.5–2 seconds after Center absence is observed.

## Existing v90.35.3.23 fixes retained

- post-maneuver stock-HUD lane clear and generation-guarded settle clear;
- no synthetic three-lane pattern in the top live Map Mode preview;
- lane head-size and body-length customization;
- physical HUD STA/viewer recovery and Map Mode diagnostics.

See `V90_35_3_24_CAPTURE_VALIDATION.md` for the offline validation against the already-collected MainVideo stream.

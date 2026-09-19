# v90.35.3.22 release notes

This revision is intentionally diagnostic-first after the 2026-09-18 field test. The existing CarPlay v8.11 capture path is retained because it continued mirroring valid MainVideo throughout the drive. The failed component was the v8.22 relay/bootstrap path.

## MainVideo
v8.23 removes historical GOP replay and starts a new iPhone client only at a fresh live IDR. iOS now waits for relay confirmation before TCP open, recovers a stuck NWConnection waiting state, performs bounded exact framed reads, keeps a good decoder/reference chain alive, and exposes a parked preflight state.

## Lane guidance
Lane arrow head size and body length are independently adjustable. The default head is wider for the 480×240 HUD while the shaft remains thin; body length can be shortened independently.

## Ambient lighting
A Center/BLEDOM BLE disconnect no longer means headlight OFF. NIGHT is latched through transient BLE transport loss, with a conservative BOTH-OFF corroboration before returning to DAY.

## Customization preview
The live preview remains truthful to the physical HUD. A separate always-populated demo preview is now shown inside customization so layout, map styling, turn guidance, speed-limit sign, ETA and lane controls can be adjusted at home.

# v90.35.3.10 — Map Mode UI refinement

## App changes

- Added persisted `laneInactiveGray` control. Inactive lane arrows stay neutral grayscale only; active/recommended lanes stay white.
- Added independent persisted horizontal and vertical center-map fade widths (0–35%).
- Simplified the Map Mode speed-limit graphic to a white rectangle containing only the black speed number.
- Simplified the live relay UI to CarPlay adapter SSID/password + Enable/Disable Map Mode.
- Relay/video status and manual recovery controls are under a collapsed Status & diagnostics disclosure.
- Removed the legacy mode-5 physical HUD block from the visible UI.
- Grouped all Map Mode image calibration under a collapsed disclosure.
- Standard `HudDescription` prose across the app starts collapsed by default.
- Before sending mode 6, the app waits briefly for one newly rendered JPEG to reach U2W.

## Paired U2W v8.15.1

The v8.15.1 delta keeps the v8.15 MainVideo/Route Guidance/session reliability fixes and changes only HUD MJPEG priming. It never sends the old known v8.13 image. The relay waits for a valid baseline 480×240 live JPEG, sends that same real frame three times to initialize the stock decoder, then continues normal live frames. During a temporary live-frame gap it sends nothing so the HUD holds the last frame.

## Preserved behavior

- v90.35.3.9.1 MainVideo freshness watchdog and Route Guidance holdover.
- v90.35.3.9.1 targeted Dashboard reconnect recovery and finalized no-Power-ON normal headlight behavior.
- Existing map crop, widget scale/position, maneuver/lane/ETA tuning.
- Mode-6 shared U2W Wi-Fi transport and Stop → Start reliability.

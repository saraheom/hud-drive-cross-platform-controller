# v90.35.3.8 — Map UI layout calibration

This is an app-only presentation revision for the already-working v90.35.3.7 + U2W v8.14.3 live relay. It intentionally does not modify the proven U2W transport or normal start sequence.

## Physical 480×240 region positioning

Left, center-map, and right widgets can each be moved with arrow buttons in 2-pixel increments. Whole-widget movement is bounded to ±20 px horizontally and ±12 px vertically. Each region has an individual center/reset control plus a global reset.

## Right-side maneuver/lane tuning

Persisted controls are added for:

- maneuver arrow size (80–140%)
- maneuver arrow boldness (mapped to progressively heavier SF Symbol weights)
- turning-street text size (80–130%)
- maneuver distance size (80–130%)
- lane-arrow size (80–150%)
- lane-arrow boldness
- lane spacing (1–8 px)
- active-lane emphasis (100–135%)
- ETA/time-left size (80–140%)
- separate fine X/Y movement for maneuver arrow, lane guidance, and ETA/time-left (2-pixel steps; ±12 px X / ±10 px Y)

All controls affect both the in-app preview and the same 480×240 JPEG rendered for the U2W relay. No route-guidance parsing, lane decoding, CarPlay MainVideo acquisition, BLE mode-6 sequence, U2W ports, or JPEG relay cadence is changed.

OBD2-first speed remains deferred. The live relay continues to render the existing app speed source for this car test.

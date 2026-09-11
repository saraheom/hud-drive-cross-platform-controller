# v90.35.1 — live U2W MainVideo map crop

## Purpose

This release replaces the v90.35 schematic-only center source with the real main CarPlay video exported by U2W v8.11. The left and right HUD widgets remain app-rendered so their size and content are user-customizable.

## Adapter source

U2W v8.11 exposes:

- `http://192.168.50.2/cgi-bin/u2wvideo-status.cgi`
- `http://192.168.50.2/cgi-bin/u2wvideo-main-stream.cgi`
- `http://192.168.50.2/cgi-bin/u2wvideo-main-snapshot.cgi`

The stream is Annex-B H.264 from the old adapter's existing **800×480 MainVideo** path. The adapter shim is passive: it does not request secondary navigation video, inject command 508, or alter Route Guidance.

`U2WMainVideoClient` incrementally splits Annex-B NAL units and submits SPS/PPS + video slices to VideoToolbox. The latest decoded `UIImage` is retained for the Map Mode renderer. No OCR is performed.

## Map appearance

- **Follow source:** render decoded pixels unchanged. If Google Maps/Apple Maps/Waze is in dark mode, the crop is dark; if the source is light, the crop is light.
- **Dark HUD:** apply reduced brightness, slightly reduced saturation and higher contrast to the same source pixels.
- **Light HUD:** apply a mild brightening/contrast filter to the same source pixels.

These modes do not change the navigation app's own theme; Dark/Light HUD are display filters only.

## Crop calibration

Three persisted controls are added:

- Map zoom: `0.80...2.60`
- Crop X: `-1.0...1.0`
- Crop Y: `-1.0...1.0`

Defaults (`zoom=1.55`, `X=+0.22`, `Y=0`) are based on the physical 800×480 Google Maps CarPlay frame decoded from the v8.10 dump, where the map occupied the center-left region after the launcher rail and before the Dashboard media pane. Full-screen Maps or a different CarPlay layout can be tuned live from the app.

## Physical Map Mode handoff

The current HUD cast remains the stock KivicCast mode-5 AP workflow:

1. while connected to U2W Wi-Fi, decode live MainVideo and live Route Guidance;
2. when Enable Map Mode on HUD is pressed, freeze the latest decoded MainVideo frame + semantic route;
3. stop U2W video/route polling before the iPhone moves to HUDWAY Wi-Fi;
4. serve the custom 480×240 MJPEG composition to the HUD;
5. run the existing native OBD `Driving velocity` overlay probe;
6. on Disable Map Mode, restore stock HUD mode 4/Freeride-or-Navigation and restart U2W video/route/media polling.

This release does **not** claim the physical HUD map remains live after the Wi-Fi handoff. Continuous live physical casting still requires validating the separate mode-6/shared-U2W network path.

## First test

Before enabling physical Map Mode:

1. Install U2W v8.11 and let CarPlay connect.
2. Start Google Maps/Apple Maps navigation.
3. In HUD Controller, open Custom Map Mode.
4. Confirm **Live U2W map source = LIVE** and decoded frame count increases.
5. Confirm the center preview visibly follows the CarPlay map.
6. Test Follow source / Dark HUD / Light HUD.
7. Tune crop sliders if necessary.
8. Only then enable physical Map Mode to test the frozen-real-map composition and native OBD speed overlay.

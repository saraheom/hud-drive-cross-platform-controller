# v30 test plan

## ScreenCaptureKit on iOS 27

Live capture:
1. Navigation → Start Full-Display Capture.
2. Apple presents the system content-sharing picker.
3. Choose the entire iPhone display once.
4. Switch to Google Maps.
5. Keep the Google Maps CarPlay companion/directions screen visible.
6. The app receives the full-display stream in the background at ~1 Hz.
7. Vision OCR extracts the visible direction text.
8. With Auto Send enabled, parsed maneuvers feed the existing HUD navigation packet pipeline.

This is full-display capture, not a Google Maps bundle-ID scraper. If another app
becomes visible, its pixels are captured instead.

Screen-lock behavior is intentionally not stopped by app code. v30 logs frame
timestamps so a physical iOS 27 test can determine whether frames continue,
freeze, or resume after lock/unlock.

## Saved screenshot test

Use "Choose Google Maps Screenshot" from Photos. It runs the same Vision OCR
and parser as live capture. This validates parsing while away from the car, but
does not test ScreenCaptureKit/background execution.

Expected example:
- `In 300 ft`
- `Turn right onto W Roosevelt Blvd`
- parsed RIGHT / ~91 m / W Roosevelt Blvd.

## Spotify

Manual Connect/Re-authorize now always clears a possibly stale App Remote token
and starts Spotify's authorization flow again. Automatic connection still uses
the Keychain token after a successful authorization. Error logs now include
NSError domain/code.

## Ambient BLEDOM

- timeout range: 1–30 seconds;
- CoreBluetooth restoration delegate is implemented;
- `bluetooth-central` background mode remains enabled;
- scan monitor is independent of foreground SwiftUI views.

iOS may still throttle broad BLE scans in the background. Physical testing is
required to determine locked-screen latency for this particular BLEDOM device.

## HUD light diagnostic

The log captured event `command=3, p1=30, p2=0` with a 32-bit value. v30 exposes
that value as an experimental raw HUD auto-brightness/sensor number (0–255
display range). Do not treat it as lux until light/dark testing proves the
relationship.

## OBD widgets

The app now stores independent Freeride and Navigation widget profiles.
- Freeride tests firmware positions 0/1.
- Navigation tests positions 2/3.

All selections are persisted. OBD connection requests are ignored if the HUD
already reports OBD connected, preventing the UI from reverting to "searching"
after a successful connection.

## Persistence

HUD settings, OBD device/profile selections, BLEDOM monitor settings, timeout,
and screen-capture auto-send preference save immediately to UserDefaults.
Spotify credentials remain in Keychain.

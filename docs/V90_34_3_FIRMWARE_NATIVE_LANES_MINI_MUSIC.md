# v90.34.3 — Firmware-native lane guidance + mini Music diagnostics

This release is intentionally **no-firmware-write**.

## Lane guidance

Reverse engineering of the stock HUDWAY Drive `HudLauncher.apk` confirmed the native `HudLanesManueverCommandPacket`:

- command = 2
- p1 = 113
- p2 = 0
- payload = `Int32 laneCount`, followed by one signed `Int32` for each lane

The firmware's network lane values are:

- 1 = straight
- 2 = right
- 3 = straight + right
- 4 = left
- 5 = straight + left

A positive value marks the lane active/recommended. A negative value marks it inactive/non-recommended.

v90.34.3 adds manual four-lane presets to the Navigation diagnostics screen. It does not yet auto-inject CarPlay lane data; field testing comes first.

## Mini Music

The stock renderer contains both `HwNotificationFrameViewMusic` and `HwNotificationFrameViewMusicMiniState`. `HwDriveCoreView.setMusicNotificationInfo()` populates both renderers, and `HudHUDWidgetsMiniState` (p1=122, p2=0, boolean payload) selects the firmware's global minimal UI state.

The Media screen adds:

- Mini Music ON + Send
- Re-send Current Track
- Restore Normal UI

The experiment intentionally does not force persistence or a left/right location until the stock rendering behavior is observed on the physical HUD.

## Safety boundary

No ADB commands, filesystem writes, APK replacement, updater commands, remounting, root operations, or firmware flashing are performed by the iOS application.

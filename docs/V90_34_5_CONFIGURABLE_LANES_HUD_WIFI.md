# v90.34.5 — configurable native lanes + HUD Wi-Fi exposure

This test release keeps the v90.34.4 recorded Apple/Google CarPlay lane replay and moves the lane presentation policy into persisted Navigation settings.

## Navigation presentation

- **Show Current Street**: defaults ON. When OFF, only the `currentStreet` field is suppressed on the wire; the upcoming road and maneuver remain available.
- **Lane Guidance**: Off / Near turn / Persistent.
- **Near-turn distance**: 0.1–1.0 mi, default 0.5 mi.
- **Persistence**: once lane data has been received for the current maneuver, the stock `HudLanesManueverCommandPacket` is reasserted every 1.5 s because the physical HUD can auto-hide its lane layer. Persistent mode cannot invent lanes before CarPlay has supplied them.

The recorded Apple Maps and Google Maps replay remains in the Xcode 26 Navigation screen so these settings can be validated while parked. Replay uses the same lane-policy coordinator as the production path.

## HUD Wi-Fi / casting network

The Navigation screen also exposes a HUD Wi-Fi toggle. It sends only the stock BLE network-preparation packets:

- Kivic mode 0 (`2/7/0` + int32 0)
- 2.4-GHz hotspot forced ON/OFF (`2/21/0`)
- KeepAlive (and full-screen restore when turning the forced AP off)

It does **not** start iOS Screen Recording/Drive Broadcast, does not send the HUD software-update start command, and does not write firmware or TCP/7980. Its purpose is to expose the HUDWAY SSID / `192.168.43.1` while the custom app remains connected over BLE for lane/Music ADB tracing.

## Current live-lane data limitation

U2W CarPlay Data Exporter v8.6 currently exports `laneGuidanceShowing` but not the decoded lane array in `u2wrgd-live.cgi`. Therefore v90.34.5 fully implements/tests the app-side display policy and native HUD lane renderer using captured real `0x5204` fixtures, but a later exporter update is still required before real-time `0x5204` lane arrays can drive this policy during a live route.

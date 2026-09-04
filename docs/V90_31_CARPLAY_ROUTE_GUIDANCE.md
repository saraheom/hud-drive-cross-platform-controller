# v90.31 — adapter-only CarPlay Route Guidance → HUD

v90.31 replaces the prior screen/OCR navigation path for normal driving. The physical HUD's automatic Navigation/Freeride mode is owned only by the matched Carlinkit U2W v8.5 Route Guidance exporter.

## Data path

```text
Google Maps / Apple Maps / Waze
  -> CarPlay iAP2 Route Guidance (0x5201 / 0x5202 / 0x5204)
  -> U2W v8.5 live exporter
  -> http://192.168.50.2/cgi-bin/u2wrgd-live.cgi
  -> RouteGuidanceAdapterClient
  -> NavigationInstruction + HudEtaPacket
  -> HUDWAY Drive BLE
```

## No OCR fallback

ScreenCaptureKit/OCR is not an automatic navigation source in v90.31. `HudNavigationController` rejects `.ocr` ownership. The app also no longer auto-resumes ScreenCaptureKit during HUD rehydration or app foregrounding. Legacy capture code remains only for diagnostics/history.

When the adapter endpoint is unavailable, route state is inactive, or the selected source's `sequence` stops advancing for 4.5 seconds, HUD Controller sends Navigation OFF and returns the HUD to its saved Freeride profile. When fresh active adapter data returns, the app reapplies the saved Navigation profile and sends Navigation ON automatically.

## Navigation-source priority

The app keeps a freshness lease for each supported source observed in the adapter stream:

1. Google Maps
2. Apple Maps
3. Waze

Only fresh active routes participate. Unknown sources remain visible in diagnostics but never automatically own the physical HUD. A stale Google Maps lease cannot block a fresh Apple Maps or Waze route.

## Route Guidance parsing

The v8.5 exporter normalizes the fields recovered from the physical v8.4 capture. `0x5201` supplies route state, current road, destination, absolute ETA, remaining time/distance, distance to the next maneuver, maneuver cursor/count, lane state, and source name. `0x5202` supplies indexed maneuver description/type/after-road/distance data. `0x5204` marks lane-guidance activity.

The iPhone maps CarPlay `CPManeuverType` values into the existing HUDWAY arrow vocabulary and sends the result through the same native maneuver BLE packet used by the prior navigation implementation.

## ETA

The original HUDWAY Android app contains a dedicated `HudEtaPacket`:

- command `2`, `p1=114`, `p2=0`
- payload: signed 64-bit big-endian absolute arrival time in milliseconds

v90.31 implements that packet. It prefers CarPlay's absolute arrival time. If that field is absent, it computes:

```text
current Unix time in ms + TimeRemainingToDestination * 1000
```

The default Navigation dashboard is:

- left: `Speedo`
- center: `Navigation`
- right: `ETA`

A one-time migration changes only the old v90.30 `Time` default to `ETA`; other explicit widget choices remain intact. The speed-limit sign/warning engine remains independent.

## Locked-phone driving

`UIBackgroundModes` uses `bluetooth-central` and `location`; ScreenCaptureKit is not a background mode. The driving location manager disables automatic pausing and enables background location updates. This keeps the normal vehicle/location session as the background execution anchor while the phone is locked, so Route Guidance polling does not depend on screen capture.

## Diagnostics

The Navigation tab includes a Route Guidance card with feed state, selected source, current road, destination, next distance, ETA, and last adapter error. Shareable logs include `CARPLAY RGD`, `CARPLAY RGD SOURCE`, `CARPLAY RGD HUD`, and `NAV ETA`.

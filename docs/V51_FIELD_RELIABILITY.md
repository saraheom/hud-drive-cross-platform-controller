# v51 Field Reliability Update

This release is based on the v50 field-tested repository and targets the August 14 Apple Maps/Google Maps drive observations.

## Screen capture lifecycle

`captureDesired` remains true until the user explicitly stops capture. Raw `SCStream` frame arrival is the capture heartbeat; Vision OCR runs independently. A stale or stopped stream immediately returns the HUD to Freeride so a stale maneuver can never remain frozen. Recovery rebuilds `SCStream` with backoff. After three failed starts using the same cached `SCContentFilter`, the filter is discarded and the app requests a fresh Entire Display selection. The Navigation screen exposes a prominent Resume Capture prompt when user interaction is required.

Apple's system content-sharing picker remains the privacy boundary. v51 does not attempt to bypass it.

## Apple Maps

- Destination phrases such as `The destination is on your right` / `left` are arrival states.
- `Proceed to the route` remains valid active navigation.
- Vision keeps up to five text candidates and prefers a decimal-bearing standalone distance candidate when available.
- Feet are converted with `ceil` before the integer-meter HUD protocol to prevent boundary loss such as 500 ft becoming ~499 ft and displaying as 400 ft.
- Route-shield OCR prefixes including `{13}`, `US 13`, `I-76`, and similar forms are removed from street text.
- Lane-guidance cards search the full bright-arrow band above the distance instead of assuming the active arrow is left of the distance label.

## Ambient BLE

The absence timeout no longer assigns to itself inside `didSet`. A clamped setter is used by SwiftUI, eliminating the recursive Observation/Stepper crash path.

## OBD-II

Reconnect attempts use a generation token so cancelled/stale Tasks cannot coexist with the current retry loop. The health loop continues to reassert the HUD-side OBD connection.

## Speed limit

The protocol still has no circular-sign option in this app. The last known speed limit is persisted so the rectangular style/value can be reasserted earlier during HUD session restoration.

## Music

Native firmware music popups can now be independently enabled/disabled with `Music / Spotify track popups`.

Further decompilation confirmed that the original dashboard `SideWidget` enum contains Speedo, MaxSpeedo, AvgSpeedo, Weather, Time, Distance, Cost, TripTime, ETA, Empty, RPM, Battery, Gasoline, GasolineConsumption, EngineCoolantTemp, and EngineOilTemp — but no Music side widget. `MusicNotificationPacket` is a separate notification category (12). Therefore v51 does not fake persistent music by repeatedly resending the center/right notification overlay.

## CarPlay prompt

v51 intentionally keeps the capture-renewal prompt in the iPhone app. A CarPlay UI requires an appropriate CarPlay app entitlement/template architecture and is not added in this release.

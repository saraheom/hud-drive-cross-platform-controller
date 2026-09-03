# v90.31 — CarPlay Route Guidance → HUD

v90.31 replaces OCR as the preferred navigation source when the matched
Carlinkit U2W v8.5 live exporter is available.

## Data path

```
CarPlay navigation app
  -> iAP2 0x5201 / 0x5202 / 0x5204
  -> U2W v8.5 live exporter
  -> http://192.168.50.2/cgi-bin/u2wrgd-live.cgi
  -> RouteGuidanceAdapterClient
  -> NavigationInstruction + HudEtaPacket
  -> HUDWAY Drive BLE
```

The existing ScreenCaptureKit/OCR path remains in the iOS 27 build as fallback.
The temporary iOS 26 build now gets structured navigation without needing
ScreenCaptureKit.

## Navigation-source priority

The app keeps a freshness lease for each Route Guidance source observed in the
adapter stream. Selection is deterministic:

1. Google Maps
2. Apple Maps
3. Waze
4. unknown/other Route Guidance source

A source remains eligible only while its iAP2 sequence is advancing and its
last update is <= 4.5 seconds old. This prevents a cached/stale Google snapshot
from permanently suppressing an active Apple Maps or Waze route.

While a fresh adapter route owns navigation, OCR may continue running but its
maneuver and Navigation OFF/ON commands are suppressed. If the adapter lease
expires, adapter ownership is released and the existing OCR pipeline can resume.

## CarPlay maneuver mapping

The adapter exports the native `CPManeuverType` raw value. v90.31 maps Apple's
0–53 maneuver enum directly to the existing HUDWAY maneuver vocabulary:
left/right/straight/U-turn, keep left/right, ramps/exits, roundabouts (including
exit number), destination, sharp turns, and slight turns.

## ETA

The original HUDWAY Android app contains a dedicated `HudEtaPacket`:

- `CommandPacket(p1=114, p2=0)`
- payload: Java `DataOutputStream.writeLong()` absolute ETA in milliseconds.

v90.31 implements the same packet as HUD protocol `2/114/0` with an 8-byte
big-endian millisecond timestamp. The Route Guidance client prefers iAP2's
absolute ETA when present; otherwise it calculates the value exactly like the
original HUDWAY app:

```
current Unix time in ms + TimeRemainingToDestination * 1000
```

The Navigation dashboard's default side widgets are now:

- left: `Speedo`
- center: `Navigation`
- right: `ETA`

A one-time migration changes only the legacy default-looking `Speedo + Time`
pair to `Speedo + ETA`; other explicit side-widget combinations remain intact.
The existing speed-limit sign/warning system is independent and remains active.

## Local adapter access

The app polls:

```
http://192.168.50.2/cgi-bin/u2wrgd-live.cgi
```

Both project flavors include a local-network privacy description and the HTTP
transport allowance required for this private adapter endpoint.

## Diagnostics

The Navigation tab includes a CarPlay Route Guidance card showing:

- feed state
- selected source
- current road
- destination
- next-maneuver distance
- calculated ETA
- last adapter error

The normal shareable HUD log also records `CARPLAY RGD`, `CARPLAY RGD SOURCE`,
`CARPLAY RGD HUD`, and `NAV ETA` events.

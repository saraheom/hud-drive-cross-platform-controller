# v24 vehicle integration test plan

## 1. HUD-managed OBD-II

The decompiled Android app does not implement a phone-side ELM327 parser for
its normal OBD path. It sends `OBDIIInternalPacket` to the HUD:

- command = 0
- param1 = 7
- param2 = 1
- payload = connect(bool), obdType(int32=0), deviceName(Java writeUTF)

The HUD reports `OBDConnectionEventPacket`:

- command = 3
- param1 = 100
- param2 = 0
- payload = supported PIDs (Java readUTF), connected(bool)

Test:
1. Connect and initialize HUD.
2. Vehicle → OBD-II.
3. Enter the Bluetooth-advertised OBD name (default `OBDII`).
4. Tap Connect OBD.
5. Watch Status + Supported PIDs + Logs.
6. Select left/right widgets and Apply.

`OBDIICustomItemInternalPacket` provides integer position and item ordinal.
JADX exposes the item enum but not named position constants. v24 therefore
tests `0 = left`, `1 = right`. Exact packets are logged so this can be corrected
quickly if physical behavior shows different position numbering.

## 2. Speed and posted speed limit

The original Android `SpeedLimitEngine` uses:
- `https://overpass-api.de/api/`
- `way[maxspeed][highway](around:400, lat, lon)`
- road-data refresh after roughly 300 m movement.

v24 reproduces that architecture on iOS:
- CoreLocation speed → native HUD SpeedNotificationPacket (category 14)
- Overpass maxspeed geometry → mph normalization → heading/distance road matching
- native HudSpeedLimitAndToleranceCommandPacket → HUD sign
- DisplaySpeedWarningCommandPacket → warning threshold

The iOS matcher uses a local point-to-segment distance plus heading score. It is
an engineering reimplementation of the decompiled behavior rather than a
byte-for-byte port of Android Location/polygon helper code.

## 3. BLEDOM ambient-light presence

`BLEDOM` is expected to be discovered only by app-level BLE scanning. It does
not need to appear under iOS Settings → Bluetooth.

v24:
- scans all BLE advertisements with duplicate reports enabled;
- matches advertised/peripheral name containing `BLEDOM`;
- on first presence transition: sends HUD auto-brightness ON;
- if unseen for the configured timeout (default 15 s): sends auto-brightness OFF.

Important physical test: determine whether BLEDOM actually stops advertising
when the vehicle ambient lights are off. If it remains powered/advertising, the
next iteration must inspect its advertisement payload or GATT state instead of
using presence.

## 4. Spotify native music packet

Track extraction still comes from Spotify App Remote.

Instead of posting a local iOS notification, v24 sends the firmware-native
MusicNotificationPacket:
- command = 1
- category/param1 = 12
- title = artist
- message = track
- package name = `com.spotify.client`

Use `Send Native HUD Music Test` first, then change Spotify tracks.


## v27 mph normalization

The complete app-side speed path now uses miles per hour:

- CoreLocation m/s → mph;
- OSM values explicitly tagged `mph` stay unchanged;
- bare OSM numeric `maxspeed` values are treated as km/h per OSM convention and converted to mph;
- OSM `knots` values are converted to mph;
- speed-limit warning tolerance is expressed in mph;
- HUD current-speed and speed-limit packets receive mph values;
- Vehicle UI/logs display mph consistently.

The HUD-managed OBD connection/custom-widget packet protocol is unchanged.

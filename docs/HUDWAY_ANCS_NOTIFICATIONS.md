# HUDWAY iPhone Notifications / ANCS

## Confirmed architecture

The decompiled HUDWAY client contains the instruction:

`Settings > Bluetooth > tap ⓘ next to Drive > Share Notifications on.`

That confirms the intended iPhone notification architecture: iOS is the ANCS
Notification Provider and HUDWAY Drive is the external ANCS Notification
Consumer. The companion app configures the HUD firmware over the proprietary
Nordic-UART command channel.

A normal app on that same iPhone cannot subscribe to classic ANCS and inspect
other apps' notification bodies.

## Confirmed HUD configuration commands

| Function | command | P1 | P2 | payload |
|---|---:|---:|---:|---|
| Notification timeout | 2 | 9 | 1 | int32 seconds |
| Filter initialization | 2 | 9 | 6 | none |
| Global notification enable | 2 | 9 | 7 | boolean |
| Per-app notification filter | 2 | 9 | 8 | bool + int32 color + int32 icon + int32 count + Java writeUTF identifiers |
| Message line count | 2 | 116 | 0 | int32 |

Known firmware aliases from `DisplayNotificationSettingCommandPacket` include:

- `com.kivic.call`
- `com.kivic.sms`
- `com.kivic.email`
- `com.kivic.music`
- `com.kivic.kakaotalk`
- `com.kivic.wechat`

The custom iOS client sends these known aliases together with likely iOS bundle
identifiers where useful. Those iOS identifiers are experimental until verified
on real hardware.

## Map experiment

Start with **All notifications** enabled and make sure **Share Notifications**
is enabled in the iPhone Bluetooth settings for HUDWAY Drive.

Then test Apple Maps, Google Maps, and Waze one at a time. Record whether the HUD
shows any navigation notification and, if so:

- application/icon;
- title/body;
- distance;
- maneuver text;
- street name;
- update frequency;
- whether the displayed notification is replaced or updated.

If map guidance reaches HUDWAY over ANCS, that confirms a useful data path to
the accessory. It does not by itself make that content readable inside the
companion iOS app; a second firmware-to-app path would still be required for
automatic conversion into HUD navigation maneuver packets.

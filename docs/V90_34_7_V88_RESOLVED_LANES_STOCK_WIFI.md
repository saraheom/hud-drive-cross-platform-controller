# v90.34.7 — U2W v8.8 resolved lanes + stock HUD Wi-Fi bootstrap

This field-fix release is based on v90.34.6.2 and addresses two independent findings from the user's physical Google Maps/U2W v8.7 drive and the original HUDWAY Wi-Fi OFF→ON ADB capture.

## 1. Live lane guidance root cause and fix

The v8.7 physical dump showed that `0x5204` TLV 1 is not a route-maneuver index. It is a composed guidance-event id. Google Maps pre-caches multiple lane events, while `0x5201` InfoType 16 selects the currently active event. U2W v8.8 resolves that event on the adapter and exports JSON schema v2 (`laneGuidanceIndex` + `guidanceEventIndex`).

v90.34.7 consumes that resolved event directly. The legacy v8.7 maneuver-index cache remains only as a backward-compatible fallback and is not used for schema v2.

The app log also proved that the native HUD maneuver packet can redraw over/clear the separate lane layer. v90.34.6 could therefore send a persistence refresh and then immediately send the maneuver packet, making Persistent and Near Turn appear ineffective. v90.34.7 fires a callback immediately after every native CarPlay maneuver delivery and queues the eligible lane packet directly behind it. The existing 1.5-second refresh remains a backup rather than the only defense against HUD auto-hide.

Presentation-setting changes also deliberately resend the maneuver first and reevaluate/send lanes second.

Near Turn continues to use live `distanceToManeuverMeters`; after an event has been activated, custom Persistent/Near Turn behavior does not depend on the stock `laneGuidanceShowing` flag remaining true.

## 2. HUD Wi-Fi bootstrap now matches the original app

The original HUDWAY ADB log proved the stock Wi-Fi ON command sequence:

1. `HudHotspotBaseband(is5G:true, forceEnable:false)`
2. `KivicMode(5)` (`IOS_KIVICCAST_MODE`)
3. remain in mode 5 while HudLauncher starts `WifiApEnabler`, `hostapd`, tethering and `dnsmasq`
4. HUD gets `wlan0=192.168.43.1/24`; laptop receives a `192.168.43.x` DHCP lease.

The previous custom implementation used 2.4 GHz, force=true, and returned to mode 4 at 1.8 seconds—before the stock firmware even started `WifiApEnabler`.

v90.34.7 now uses the exact captured 5-GHz/force=false sequence and remains in mode 5. After roughly five seconds, the UI asks the user to join the HUDWAY Wi-Fi.

A separate **Pin AP + Return HUD Mode 4** diagnostic is available only after DHCP succeeds. It sends `is5G:true, forceEnable:true`, waits 350 ms, then restores mode 4/full-screen to test whether the already-created AP can remain alive while native HUD navigation returns.

Turning exposure off matches the stock OFF transition: 5 GHz, force=false, then mode 4.

## Safety boundary

This release does not invoke the HUD software-update command, TCP/7980 transfer path, ADB write, filesystem write, APK replacement, or firmware update. The Wi-Fi work is intended to establish a reliable ADB/network path before a separately reviewed reversible firmware-upload workflow is added later.

The Apple/Google recorded lane replay remains available for one final comparison cycle.

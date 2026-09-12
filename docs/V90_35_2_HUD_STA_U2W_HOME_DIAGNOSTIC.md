# v90.35.2 — HUD-as-STA → U2W home diagnostic

This release tests the stock iOS casting STA path without moving the iPhone away from the Carlinkit/U2W Wi-Fi network.

## Network topology under test

- U2W remains the existing access point at `192.168.50.2`.
- iPhone remains associated to U2W.
- HUD Controller sends stock `IOS_KIVICCAST_STA_MODE` (`mode=6`) over BLE.
- HUD Controller sends the recovered `WifiSTAModeCommandPacket` (`2/16/0`) containing the U2W SSID, password, and security type 2.
- HUD returns `WifiSTAStatusEventPacket` (`3/6/0`) with status/reason/address; v90.35.2 parses and displays it.
- U2W v8.13 listens for the HUD's `KVMJPEG/1.0` discovery on UDP 15320 and advertises an MJPEG stream at `http://192.168.50.2:15330`.
- The v8.13 stream is a known static 480×240 test image. CarPlay is not required for this diagnostic.

The v8.13 image does not reconfigure `wlan0`, `hostapd`, channels, DHCP, or the existing U2W AP. This directly tests whether the HUD can join the U2W AP as a second station while the iPhone remains connected.

## UI changes requested for v90.35.2

- Navigation tab controls use the original green `HudTheme.accent` again.
- Custom Map Mode control accents use the same green UI theme; the real/source map pixels are not recolored by this change.
- The temporary **Speed Marker Probe** card is removed from Vehicle. Its low-level diagnostic methods remain in source for regression/history but are no longer exposed in the user UI.

## Home test

1. Install U2W v8.13 and reconnect the iPhone to the normal U2W/Carlinkit Wi-Fi.
2. Keep the HUD connected to the iPhone over BLE.
3. In Navigation → Custom Map Mode → **HUD → U2W Wi-Fi home diagnostic**, enter the actual U2W SSID/password.
4. Tap **Start home bridge test**. Do not enable the legacy mode-5 Map Mode and do not join HUDWAY Drive Wi-Fi.
5. Watch **HUD STA status** and **HUD STA IP**. A successful association is status 1 with a `192.168.50.x` address.
6. If KivicCast discovery succeeds, the HUD should display the known v8.13 test image.
7. Open `http://192.168.50.2/cgi-bin/u2whud-status.cgi` and save the result regardless of success/failure.
8. Tap **Stop test + restore HUD** when finished.

## Interpretation

- STA status 1 + no image: Wi-Fi topology works; diagnose KivicCast discovery/HTTP next.
- STA failure / timeout: inspect returned reason plus U2W status/ARP/DHCP evidence.
- iPhone disconnects when HUD joins: U2W AP is effectively single-station in this configuration.
- Image appears: the network architecture is validated, and a later release can replace the static JPEG with iPhone-rendered frames posted to U2W.

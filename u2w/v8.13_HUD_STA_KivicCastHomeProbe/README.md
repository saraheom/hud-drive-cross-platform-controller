# U2W HUD-as-STA KivicCast Home Probe v8.13

Target: old Carlinkit U2W running `software_version=2021.03.06.1343`.

v8.13 is the inverse of the unsuccessful v8.12 AP+STA experiment. It does **not** ask the U2W radio to join the HUD. The U2W remains the normal access point at `192.168.50.2`; HUD Controller v90.35.2 tells the HUD over BLE to join that existing AP using the stock `IOS_KIVICCAST_STA_MODE` (6) + `WifiSTAModeCommandPacket` path.

The adapter contributes only a known-image KivicCast server:

- UDP discovery: `0.0.0.0:15320`
- advertised stream: `http://192.168.50.2:15330`
- stream format: multipart MJPEG
- test frame: static 480×240 JPEG

This can be tested at home without active CarPlay.

## Install

Upload `U2W_Update_v8.13_HUD_STA_KivicCastHomeProbe.img` using the same U2W `upload.cgi` workflow as previous images. The image checks product type/version and replaces only the prior `/usr/lib/u2whud` home-probe namespace plus `u2whud-*.cgi`. It does not edit `hostapd`, DHCP, `wlan0`, route-guidance exporter files, or MainVideo exporter files.

After reboot/reconnect, the preferred test is from HUD Controller v90.35.2. The app calls:

`http://192.168.50.2/cgi-bin/u2whud-start.cgi`

before sending mode 6 / STA credentials over BLE.

Manual endpoints:

- `/cgi-bin/u2whud-start.cgi` — start known-image KivicCast server
- `/cgi-bin/u2whud-status.cgi` — cast log, ARP table, DHCP-lease evidence, listener state
- `/cgi-bin/u2whud-stop.cgi` — stop the test server

## Success criteria

1. The iPhone remains connected to the U2W AP.
2. HUD Controller receives `WifiSTAStatusEventPacket` status `1` and a `192.168.50.x` address for the HUD.
3. `/cgi-bin/u2whud-status.cgi` shows `waiting-kvmjpeg-discovery`, then `discovery-replied`, then `tcp-client-connected`.
4. The physical HUD displays the static 480×240 U2W → HUD bridge test image.

If step 2 succeeds but step 3/4 fails, shared Wi-Fi is proven and the remaining work is KivicCast protocol alignment. If the HUD cannot obtain an address or the iPhone is evicted when the HUD associates, the U2W AP/client limit is the blocker.

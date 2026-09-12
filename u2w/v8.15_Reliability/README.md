# U2W v8.15 — MainVideo + Route Guidance + HUD relay reliability

Target: Carlinkit U2W `software_version=2021.03.06.1343`, `product_type=U2W`.

This release is deliberately narrow. It keeps the proven v8.8 Route Guidance parser, v8.11 AppleCarPlay MainVideo capture hook, and v8.14.3 HUD-as-STA/KivicCast transport, while fixing three field failures observed during the September 12 car test.

## Changes

1. **Rotation-safe MainVideo HTTP stream**
   - Replaces the BusyBox `cat + tail -f` CGI follower with a tiny ARM streamer.
   - The v8.11 exporter still rotates the same `/tmp/u2w_mainvideo_live.h264` file at a fresh SPS around 12 MiB.
   - The new streamer detects same-inode truncation (`end < current_position`), seeks to the new generation, and keeps the same HTTP response alive.
   - No CarPlay video decoding/transcoding occurs on U2W.

2. **Route Guidance / Now Playing JSON publication hardening**
   - Keeps `.tmp -> rename` atomic publication.
   - Adds separate in-process locks around the shared Route Guidance and media JSON scratch buffers + temporary file writes, preventing concurrent hook threads from corrupting a snapshot.
   - A normal adapter power-cycle after installation activates the newly mapped preload shim.

3. **Session-scoped HUD relay state**
   - Every `u2whud-start.cgi` creates a new `session_id` and clears per-session discovery/client/live-frame markers.
   - `u2whud-status.cgi` reports only the current session rather than grepping historical logs.
   - `u2whud-stop.cgi` idles the display session but leaves healthy ingress/discovery/MJPEG daemons running and preserves the last frame, reducing Stop -> Start rebind/discovery races.

## Preserved behavior

- U2W AP remains `192.168.50.2`; hostapd/DHCP/SSID/channel are not modified.
- Ports remain UDP 15320 (KivicCast discovery), TCP 15330 (HUD MJPEG), TCP 15331 (iPhone JPEG ingress).
- The iPhone and HUD remain simultaneously on the U2W AP.
- v8.14.3 known-good fallback JPEG and MJPEG behavior are retained.
- Existing v8.8 Route Guidance protocol parsing and v8.11 passive MainVideo capture remain the base implementation.

## Install

Upload `U2W_Update_v8.15_Reliability.img` as `U2W_Update.img` through the same Carlinkit update endpoint used for previous custom images. After installation completes, **fully power-cycle the Carlinkit adapter** so `ARMiPhoneIAP2` starts with the v8.15 preload shim.

Example from Windows PowerShell while connected to the adapter Wi-Fi:

```powershell
curl.exe -v `
  -F "file=@.\U2W_Update_v8.15_Reliability.img;filename=U2W_Update.img;type=application/octet-stream" `
  "http://192.168.50.2/cgi-bin/upload.cgi"
```

The installer is gated to the exact target software/product and verifies the saved original `ARMiPhoneIAP2` SHA-1 before changing the preload shim. It also requires the existing v8.11 MainVideo marker.

## Status endpoints

- `http://192.168.50.2/cgi-bin/u2wrgd-status.cgi`
- `http://192.168.50.2/cgi-bin/u2wrgd-live.cgi`
- `http://192.168.50.2/cgi-bin/u2wvideo-main-stream.cgi`
- `http://192.168.50.2/cgi-bin/u2whud-status.cgi`

The HUD status endpoint now includes `session_id`, `session_discovery_seen`, `session_client_seen`, `session_live_frame_sent`, and current `hud_mjpeg_established`.

## Rollback

`U2W_Update_v8.15_Reliability_UNINSTALL.img` restores the immediately preceding components: v8.8 Route Guidance preload shim, v8.11 shell MainVideo follower, and v8.14.3 HUD relay/CGIs. Power-cycle afterward.

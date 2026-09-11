# U2W Main CarPlay Video Live Exporter v8.11

Target only: **Carlinkit U2W / software 2021.03.06.1343**.

v8.11 replaces the v8.10 active secondary-navigation experiment with a narrower **passive** exporter. The September 11 v8.10 dump proved that this old adapter continuously carries the real main CarPlay H.264 stream at **800×480** while secondary navigation video type `0x2C` remains absent. v8.11 mirrors that already-existing main stream and makes it available to the iPhone app over the adapter's normal HTTP server.

## Endpoints

After installation and reboot:

- status: `http://192.168.50.2/cgi-bin/u2wvideo-status.cgi`
- live Annex-B H.264: `http://192.168.50.2/cgi-bin/u2wvideo-main-stream.cgi`
- finite current H.264 segment: `http://192.168.50.2/cgi-bin/u2wvideo-main-snapshot.cgi`
- diagnostic dump: `http://192.168.50.2/cgi-bin/u2wvideo-dump.cgi`

The live stream is the **complete CarPlay MainVideo frame**, not a fabricated map. HUD Controller v90.35.1 decodes it with iOS VideoToolbox and crops the map region locally. Therefore **Follow source** preserves the actual Google Maps / Apple Maps / Waze day/night appearance. The app's optional Dark HUD / Light HUD modes are post-processing filters on the same source pixels.

## Safety boundary

v8.11 does **not**:

- inject `naviScreenInfo`;
- send/echo command 508 or 509;
- request a secondary navigation screen;
- consume or replace CarPlay bytes;
- modify the v8.8 Route Guidance / Now Playing / lane exporter.

The shim is loaded only into `AppleCarPlay`. It mirrors the sustained outbound H.264 fd to `/tmp/u2w_mainvideo_live.h264`. The rolling file is bounded and rotates at a fresh SPS after roughly 12 MiB so a new segment starts at a decoder-friendly boundary.

The install image also retires the v8.10 **driver-side active probe wrapper** and restores the exact saved stock `ARMadb-driver`. Only `AppleCarPlay` remains wrapped for passive video observation.

## Install

With the computer connected to the U2W Wi-Fi:

```powershell
cd "C:\Users\sjeom\Downloads"
Get-FileHash ".\U2W_Update_v8.11_MainVideoLive.img" -Algorithm SHA256
curl.exe -v -F "file=@.\U2W_Update_v8.11_MainVideoLive.img;filename=U2W_Update.img;type=application/octet-stream" "http://192.168.50.2/cgi-bin/upload.cgi"
```

Let the adapter update and reboot. Reconnect to its Wi-Fi and check:

```powershell
curl.exe "http://192.168.50.2/cgi-bin/u2wvideo-status.cgi"
```

At home, before CarPlay is active, `live_file_bytes=0` is normal.

## In-car test

1. Let wireless CarPlay connect normally.
2. Open Google Maps or Apple Maps. A real route is preferred.
3. On the iPhone, open HUD Controller → Navigation → Custom Map Mode.
4. The **Live U2W map source** block should change to `LIVE`, the frame counter should increase, and the preview center should show the real CarPlay map crop.
5. Try **Follow source / Dark HUD / Light HUD** and adjust Map zoom / Crop X / Crop Y if necessary.
6. Do this live-source validation **before** enabling the physical HUD cast.

You can also verify the adapter directly:

```powershell
curl.exe "http://192.168.50.2/cgi-bin/u2wvideo-status.cgi"
curl.exe -o "u2w-main-current.h264" "http://192.168.50.2/cgi-bin/u2wvideo-main-snapshot.cgi"
```

A healthy status should show `exporter_active=YES`, `main_fd` non-negative, `segment_bytes` increasing, and H.264 SPS/PPS/IDR/slice counters increasing.

## Current network limitation for physical Map Mode

The live U2W video source and the HUDWAY KivicCast AP are two different Wi-Fi networks. v90.35.1 therefore behaves deliberately as follows:

- while the iPhone is on U2W Wi-Fi, the **in-app Map Mode preview is truly live**;
- when you tap **Enable Map Mode on HUD**, the app freezes the latest decoded U2W frame and route state before asking you to join the HUDWAY AP;
- the physical HUD cast uses that frozen real map frame while we test the cast + native OBD-speed overlay;
- a continuously live map on the physical HUD still requires the separate shared-network/STA experiment to prove that this U2W can accept the HUD as another client and permit client-to-client traffic.

This distinction is intentional; the app does not pretend a frozen frame is live.

## Recovery / uninstall

`U2W_Update_v8.11_MainVideoLive_UNINSTALL.img` restores the exact saved stock `ARMadb-driver` and `AppleCarPlay`, removes only the video-exporter shim/endpoints, and leaves the v8.8 Route Guidance exporter untouched.

# U2W v8.21 — Persistent decoder-safe MainVideo GOP cache

Target: Carlinkit U2W `2021.03.06.1343`, with v8.11 MainVideo exporter and v8.20 marker already installed.

The afternoon 2026-09-17 capture showed that an active-navigation rolling generation can contain valid non-IDR slices but no SPS/PPS/IDR. v8.20 waited forever for a bootstrap inside that single generation. v8.21 moves bootstrap continuity into a tiny standalone cache daemon.

## What changes

- Installs `/usr/lib/u2wvideo/u2w_mainvideo_cache`.
- Adds `u2wvideo-cache-start.cgi` and `u2wvideo-cache-status.cgi`.
- Replaces only `u2wvideo-main-stream.cgi` with the cache-backed fail-fast streamer.
- Does **not** modify or restart AppleCarPlay.
- Does **not** modify the v8.11 exporter, Route Guidance, Now Playing, or HUD frame relay.

The cache daemon continuously tails the existing v8.11 rolling H.264 file. When it sees a valid IDR and has plausible SPS/PPS, it starts a fresh cache with those parameter sets and the IDR, then appends following H.264 NALs across file rotations. A new HTTP client therefore receives a decoder-safe GOP even when the current exporter generation begins with P-slices.

If the cache has not captured a decoder-safe GOP yet, the MainVideo CGI returns HTTP 503 within roughly two seconds instead of waiting indefinitely.

## Install

```powershell
cd "$env:USERPROFILE\Downloads"
$img = ".\U2W_Update_v8.21_PersistentGOPCache.img"
Get-FileHash $img -Algorithm SHA256
curl.exe -v -F "file=@$img;filename=U2W_Update.img;type=application/octet-stream" "http://192.168.50.2/cgi-bin/upload.cgi"
```

After reboot/reconnect, the iOS app will start the cache helper automatically. Manual checks:

```powershell
curl.exe "http://192.168.50.2/cgi-bin/u2wvideo-cache-start.cgi"
curl.exe "http://192.168.50.2/cgi-bin/u2wvideo-cache-status.cgi"
curl.exe -sS -D - --max-time 2 -o NUL "http://192.168.50.2/cgi-bin/u2wvideo-main-stream.cgi"
```

A ready stream reports `X-U2W-Streamer: v8.21-gop-cache-relay` and `X-U2W-Cache: ready`. A not-yet-ready cache returns HTTP 503 rather than blocking.

The uninstall image restores the exact bundled v8.20 MainVideo streamer and removes only the v8.21 cache helper/endpoints.

# U2W v8.19 — Safe MainVideo Filter

Target adapter: **U2W / software 2021.03.06.1343**.

Prerequisites: the stable **v8.11 MainVideo exporter** and **v8.17 LatestFrame streamer marker**. This release intentionally does **not** use the v8.18 fd-reselection preload shim.

## Safety scope

v8.19 changes exactly one runtime file:

`/etc/boa/cgi-bin/u2wvideo-main-stream.cgi`

It does **not** replace or preload `AppleCarPlay`, does not hook `write/send/writev/sendmsg/close`, does not restart CarPlay, and does not change Route Guidance, Now Playing, Wi-Fi/AP configuration, or the iPhone→U2W→HUD JPEG relay. The validated v8.11 exporter remains byte-for-byte untouched.

This is the key safety difference from v8.18. If the v8.19 CGI process fails, it affects only that HTTP MainVideo request; it is not executing inside the CarPlay process.

## Filter behavior

Field captures showed the v8.11 rolling file contains real 800×480 H.264 plus byte sequences that can accidentally look like Annex-B NAL start codes. The v8.17 streamer selected apparent SPS/PPS/IDR markers by type alone. v8.19 validates before emitting:

- `forbidden_zero_bit == 0`
- SPS syntax and **exact 800×480** dimensions
- SPS/PPS maximum size of 256 bytes
- PPS must reference the accepted SPS
- IDR/P slices must reference the accepted PPS and start at `first_mb_in_slice == 0`
- output uses canonical four-byte Annex-B start codes
- malformed/unknown NALs are dropped instead of replacing decoder state

The v8.17 delivered-tail generation fingerprint is retained. On a rolling-file generation change, the CGI discards its parser state and searches the new file for a validated SPS/PPS/IDR bootstrap.

When no trustworthy GOP is present, the CGI retries at a deliberately low rate (1 second) instead of busy-scanning the adapter.

## Install

Verify the image:

```powershell
Get-FileHash ".\U2W_Update_v8.19_SafeMainVideoFilter.img" -Algorithm SHA256
```

Upload as the normal U2W update filename:

```powershell
curl.exe -v `
  -F "file=@.\U2W_Update_v8.19_SafeMainVideoFilter.img;filename=U2W_Update.img;type=application/octet-stream" `
  "http://192.168.50.2/cgi-bin/upload.cgi"
```

A full Carlinkit power cycle is **not required by v8.19**, because no preload library or AppleCarPlay process is changed. Ending/restarting Map Mode is enough to create a new CGI process. A normal power cycle is still safe if you prefer a clean test session.

Verify the new streamer header:

```powershell
curl.exe -sS -D - -o NUL --max-time 5 `
  "http://192.168.50.2/cgi-bin/u2wvideo-main-stream.cgi"
```

Expected:

`X-U2W-Streamer: v8.19-safe-mainvideo-filter`

and:

`X-U2W-AppleCarPlay-Hooks: none`

`u2wvideo-status.cgi` will continue to identify the **v8.11 exporter**. That is intentional.

## Uninstall

`U2W_Update_v8.19_SafeMainVideoFilter_UNINSTALL.img` restores the exact v8.17 streamer binary bundled from the stable baseline. It does not alter the v8.11 exporter.

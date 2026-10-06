# U2W v8.25 — Validated GOP Recovery Relay

This is the paired adapter update for HUD Controller **v90.35.3.24.6**.

## Why it exists

The 2026-09-21 evening road test proved that the stable v8.11 AppleCarPlay MainVideo exporter continued to receive H.264 and later observed many fresh IDRs, while the v8.24 TCP relay could temporarily have no usable recent in-memory anchor. The iPhone then had to wait too long for a clean decoder bootstrap.

v8.25 replaces the fragile long-lived recent-anchor spool with a **validated rolling-file GOP rescan** at client/recovery boundaries:

1. Keep the existing v8.11 MainVideo exporter untouched.
2. When a TCP/15332 client connects, scan the current bounded `/tmp/u2w_mainvideo_live.h264` generation.
3. Select the newest syntactically validated **800×480 SPS + matching PPS + IDR**.
4. Replay only that newest GOP up to the current live edge, capped at **48 MiB**. Replay is streamed from the rolling file (not buffered as a 48 MiB RAM cache) and is paced at about 4 ms per validated frame to avoid the historical burst behavior.
5. Continue with validated live NALs.
6. On v8.11 file-generation rotation, reset validation and re-seed the connected client from the newest validated GOP in the new generation when possible.
7. If no valid bounded GOP exists, wait for the next validated live IDR rather than replaying arbitrary history.

The wire format remains `[u32BE length][H.264 NAL]` and uses `U2WH2643`, already accepted by the paired iOS app.

## Deliberately unchanged

- AppleCarPlay process / v8.11 capture hook
- Route Guidance exporter
- Now Playing exporter
- HUD JPEG/MJPEG relay v8.15.1
- Boa video streaming (TCP/15332 remains a dedicated native relay)

## Firmware files

Install:

`U2W_Update_v8.25_ValidatedGOPRecovery.img`

Rollback:

`U2W_Update_v8.25_ValidatedGOPRecovery_UNINSTALL.img`

The rollback payload restores the **bundled v8.24 source revision** (`U2WH2643`, 4 MiB cap), which is not byte-identical to the older field v8.24 (`U2WH2642`, 1.5 MiB cap) that was previously flashed in the car.

## Diagnostics

`/cgi-bin/u2wvideo-relay-status.cgi` reports, among other fields:

- `file_gop_scan_attempts`
- `file_gop_scan_misses`
- `file_gop_cap_rejects`
- `file_gop_bootstraps`
- `live_idr_bootstraps`
- `generation_reseeds`
- `last_bootstrap_mode`
- `last_bootstrap_bytes`
- validation/rejection and client-send counters

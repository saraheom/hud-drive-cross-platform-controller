# U2W v8.26 — Persistent validated-GOP bridge

Paired app: **HUD Controller v90.35.3.24.7**.
Target: old Carlinkit U2W `software_version=2021.03.06.1343`, `product_type=U2W`, with the proven v8.11 MainVideo exporter and v8.15.1 HUD JPEG relay already installed.

## Why v8.26 exists

The 2026-09-22 road test isolated the v8.25 failure mode. The v8.11 exporter remained healthy and observed many SPS/PPS/IDR candidates, but v8.25 treated each rolling-file replacement as a decoder epoch. It repeatedly discarded parameter continuity, returned to `WAITING_VALIDATED_GOP`, and rescanned the current rolling file. The field status ended at 126 scans / 125 misses and 102 client sessions / 100 replacements.

v8.26 treats a v8.11 rolling-file change as a **storage boundary, not a codec boundary**.

## Data path

`AppleCarPlay -> unchanged v8.11 /tmp/u2w_mainvideo_live.h264 -> v8.26 TCP/15332 -> iPhone`

Wire format:

`U2WH2644` followed by repeated `[u32 big-endian NAL length][H.264 NAL]` records.

## Recovery model

- The strong 800×480 SPS/PPS/slice validator from v8.25 is retained.
- Validated codec/parser state survives ordinary v8.11 file rotation.
- The same relay process maintains one bounded, length-framed GOP recovery cache at `/tmp/u2w_mainvideo_validated_gop.cache`.
- Cache construction starts at a validated IDR and becomes replayable only after the IDR frame is known complete (first following P-frame boundary).
- New/recovering clients first receive the persistent validated GOP cache. If it is unavailable, a current-file validated-GOP scan is attempted once, then the same TCP client waits for the next validated live IDR.
- Cache writes and replay are coordinated by the **same process**. There is no separate v8.21 cache daemon and no long-lived Boa video CGI, avoiding the old cache-reader/truncation race.
- The cache is capped at 48 MiB. Overflow invalidates the cache and falls back to a fresh validated live IDR rather than forwarding arbitrary history.
- An actual SPS/PPS configuration change invalidates the old cache and starts a new codec epoch. A rolling-file change by itself does not.

## Deliberately unchanged

- AppleCarPlay and the v8.11 capture hook
- Route Guidance exporter
- Now Playing exporter
- HUD JPEG/MJPEG relay v8.15.1
- Carlinkit AP configuration

## Firmware files

Install:

`U2W_Update_v8.26_PersistentGOPBridge.img`

Rollback:

`U2W_Update_v8.26_PersistentGOPBridge_UNINSTALL.img`

Rollback restores the bundled v8.25 MainVideo relay only; it does not touch v8.11, Route Guidance, media, or the HUD frame relay.

## Useful status fields

`/cgi-bin/u2wvideo-relay-status.cgi` exposes:

- `client_state`
- `gop_cache_ready`
- `gop_cache_building`
- `gop_cache_bytes`
- `gop_cache_frames`
- `gop_cache_replays`
- `gop_cache_invalidations`
- `codec_epoch_resets`
- legacy current-file scan counters
- `source_bytes_low32`
- `source_generation_changes`
- client/session/send-failure counters

The paired iOS app also watches `source_bytes_low32`. While the relay is explicitly waiting for a bootstrap and source bytes continue to advance, the app preserves the same TCP connection instead of creating the v8.25 reconnect storm.

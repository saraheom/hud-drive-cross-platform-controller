# U2W v8.23 — Live-IDR MainVideo Relay

This revision replaces the v8.22 cached-GOP bootstrap after the 2026-09-18 road test showed the iPhone could connect to TCP/15332 but the adapter completed zero cached-GOP bootstraps and repeatedly failed while attempting to send multi-megabyte historical GOPs.

## Architecture

The stable v8.11 exporter remains the sole CarPlay capture mechanism:

`AppleCarPlay → v8.11 /tmp/u2w_mainvideo_live.h264 → v8.23 relay TCP/15332 → iPhone sanitizer/VideoToolbox`

The v8.23 relay:

- never opens or patches AppleCarPlay;
- never carries long-lived video through Boa/CGI;
- sends the 8-byte wire magic `U2WH2642`;
- frames each raw H.264 NAL as `[u32 big-endian length][NAL]`;
- does **not** replay a historical/cached GOP;
- remembers only the latest SPS/PPS needed for decoder bootstrap;
- makes a new iPhone connection wait for the **next naturally arriving live IDR**;
- at that live IDR sends SPS + PPS + IDR, then only subsequent live NALs at their natural arrival rate;
- preserves Annex-B parser state across v8.11 rolling-file generations so a NAL split across a normal mirror rollover is not discarded;
- keeps one bounded client and uses an 8-second send timeout per NAL.

The v8.11 exporter, Route Guidance, Now Playing, and AppleCarPlay are not modified.

## HUD JPEG relay

v8.23 restores the exact v8.15.1 `u2whud_cast_relay` binary. The v8.22 two-second HUD MJPEG sender timeout was not needed during the pre-crash portion of the field test, where speed and maneuver data continued updating correctly on the physical HUD.

## Diagnostics

Start/ensure:

`http://192.168.50.2/cgi-bin/u2wvideo-relay-start.cgi`

Status:

`http://192.168.50.2/cgi-bin/u2wvideo-relay-status.cgi`

Important fields include:

- `relay_process`
- `client_state=NO_CLIENT|WAITING_LIVE_IDR|LIVE`
- `startup_scan_complete`
- `have_sps`, `have_pps`
- `source_bytes_low32`, `source_generation_changes`
- `sps`, `pps`, `idr`, `slices`
- `client_sessions`, `client_live_bootstraps`, `client_send_failures`
- `pre_idr_slices_dropped`
- `last_bootstrap_source_bytes`, `last_nal_type`

The tail of `/tmp/u2w_mainvideo_relay.log` is included in the status CGI output.

## Parked preflight

For the next field validation, do not begin a drive until the iOS app reports `LIVE • frames advancing` and the map-frame counter is visibly increasing. The expected sequence is:

`relay RUNNING → TCP READY → WAITING_LIVE_IDR → fresh SPS/PPS/IDR → VideoToolbox → LIVE`

If the app remains at `WAITING_LIVE_IDR`, start a Google Maps route while still parked. Prior captures show route transitions generate fresh decoder bootstrap material. If `LIVE` is not reached within about one minute after route start, collect the iOS log plus `u2wvideo-relay-status.cgi` and `u2wvideo-status.cgi` without beginning the drive.

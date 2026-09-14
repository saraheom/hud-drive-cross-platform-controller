# v90.35.3.13.2 — MainVideo / HUD viewer / OBD framing stabilization

This is an **iOS-app-only stabilization revision** on top of v90.35.3.13.1.1. The paired adapter image remains **U2W v8.17 LatestFrame** byte-for-byte unchanged.

## MainVideo

The 2026-09-14 road log showed fresh H.264 bytes while VideoToolbox repeatedly rejected format descriptions (`-12712`), causing a rapid stream-worker reconnect loop. v90.35.3.13.2:

- stages SPS/PPS candidates separately from the accepted decoder pair;
- strips Annex-B trailing zero alignment bytes from parsed NALs;
- validates a candidate format description and creates its VideoToolbox session **before** replacing the existing decoder;
- preserves the last-known-good SPS/PPS and decoder session across HTTP latest-GOP reseeds;
- rebuilds the decoder from the accepted pair after repeated decode errors;
- reseeds the same serial stream worker instead of creating a new worker every watchdog cycle;
- uses a 5 s fresh-byte/no-frame threshold and 8 s reseed cooldown, while source silence remains 12 s;
- keeps the existing latest-frame mailbox and 5 fps (200 ms) physical HUD render cadence.

## Physical HUD relay readiness

The U2W status file proved `hud_mjpeg_established=YES` can reflect a stale/process-wide socket even when the **current relay session** has `session_client_seen=NO` and `session_live_frame_sent=NO`.

v90.35.3.13.2 therefore treats a v8.15.1+ session as ready only when the current session has both:

- `session_client_seen=YES`, and
- `session_live_frame_sent=YES`.

If STA is still associated but no current HUD viewer attaches within 8 s, the app performs **one** automatic viewer recreation using the already field-validated sequence:

`mode 4 -> 900 ms settle -> mode 6`

No Wi-Fi credentials are resent by this automatic recovery. There is no repeated kick loop.

## OBD diagnostic framing

The 2026-09-14 forensic transfer showed repeated/interleaved BLE continuation notifications and a returned `LOG_CATEGORY_CRUSH` stream despite requesting `LOG_CATEGORY_OBD`.

This revision:

- recognizes only the legal HUD escapes `7D 7F`, `7D 7E`, and `7D 00`;
- lets a literal nested STX resynchronize after an invalid/dangling escape;
- retains every notification in the raw `.bin` capture while suppressing immediate duplicate non-STX continuation fragments from the parser and verbose `RX CHUNK` text log, reducing forensic-log pressure on the main actor;
- requires plausible diagnostic headers and **exact** `available == declared chunkSize` before saving a chunk;
- rejects extra/truncated bodies instead of silently taking the first declared bytes;
- can assemble the first structurally valid returned diagnostic category even when it differs from the requested OBD label;
- detects conflicting duplicate chunk indices and retains the first exact frame.

These changes improve the fidelity of the next OBD capture but do **not** claim that native numeric OBD speed has been found yet.

## Unchanged

- U2W v8.17 install/uninstall images
- route guidance / lane guidance / now-playing paths
- ambient-light behavior
- current Map Mode layout/settings
- content-blind CarPlay crop
- physical HUD cadence: 5 fps

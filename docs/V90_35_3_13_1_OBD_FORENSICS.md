# v90.35.3.13.1 — OBD forensic logging on the v90.35.3.13 latest-frame baseline

This is an **app-only** diagnostic revision. The paired adapter remains **U2W v8.17 LatestFrame** with no reflash required when v8.17 is already installed.

## MainVideo / Map Mode

The v90.35.3.13 latest-frame MainVideo work is unchanged. The center CarPlay crop remains content-blind and the physical HUD relay remains fixed at 5 fps (200 ms) for the reliability road test.

## Why add OBD forensics now

The 2026-09-13 drive proved that the stock HUD accepts the `LOG_CATEGORY_OBD` request and reports OBD logs present, but the returned diagnostic stream frequently identified itself as `LOG_CATEGORY_CRUSH` and many frames failed the existing chunk parser. The purpose of this revision is to preserve enough evidence to determine whether the mismatch is category selection, duplicate/interleaved BLE notifications, chunk framing, or an unrecognized stock HUD diagnostic format.

## New diagnostic capture

When **Request latest HUD OBD logs** is pressed, the app now:

- keeps a bounded 8 MiB copy of the exact HUD BLE byte stream **before** the diagnostic parser touches it;
- logs the requested category and every returned diagnostic category;
- logs diagnostic frame number, wire/body byte counts, total size, chunk count/index, declared chunk size, and actual bytes available;
- explicitly logs category mismatches such as requested `LOG_CATEGORY_OBD` vs returned `LOG_CATEGORY_CRUSH`;
- preserves malformed packets instead of losing the only forensic copy;
- scans diagnostic payloads for binary `01 0D` / `41 0D`, ASCII `010D` / `410D`, common ELM327 tokens, ZIP/PK signatures, and numeric values close to simultaneous GPS mph/km/h;
- saves the raw capture as `HUD_OBD_RawBLE_<timestamp>.bin` when the OBD ZIP completes or when **Stop & save raw** is pressed.

The raw `.bin` is the concatenated on-wire BLE byte stream from the diagnostic window. STX/ETX/escape framing is preserved so the stream can be replayed through the same HUD frame extractor offline.

## OBD_DRIVING_VELOCITY forced window

The existing 12-second native speed visual probe is unchanged functionally, but it now opens a short forced forensic window. During the window **every** HUD RX body is logged as `OBD PROBE RX` with:

- command/p1/p2;
- full body hex (bounded per line);
- simultaneous GPS mph/km/h;
- scalar candidates;
- PID/ELM signature hits.

The automatic Map Mode stock OBD overlay probe also receives a short forced forensic window.

## Intentionally unchanged

- no second direct iPhone-to-OBD connection;
- no new PID requests beyond the existing stock HUD `OBD_DRIVING_VELOCITY` visual probe;
- no attempt yet to promote an unknown byte into production vehicle speed;
- no route-guidance, Now Playing, speed-limit, ambient-light, STA, or U2W relay behavior changes;
- U2W v8.17 is unchanged.

## Suggested commute test

1. Drive with Map Mode normally and prioritize validating continuous live MainVideo at 5 fps.
2. Once moving and HUD-side OBD is confirmed, run the existing 12-second native OBD speed probe once.
3. After arriving and while the HUD is still powered, tap **Request latest HUD OBD logs**.
4. Let the transfer run. If a ZIP becomes ready, share it. If it does not complete, tap **Stop & save raw** before powering the HUD off.
5. Export/share the normal HUD log plus `HUD_OBD_RawBLE_*.bin` (and the ZIP if one was produced).

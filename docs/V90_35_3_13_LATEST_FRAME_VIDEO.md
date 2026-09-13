# v90.35.3.13 + U2W v8.17 — latest-frame MainVideo reliability

## Priority

This revision is intentionally centered on one requirement: while Map Mode is enabled, the center CarPlay crop must remain live and update the physical HUD at the existing **5 fps** relay cadence without requiring manual MainVideo restarts.

The center crop is now treated as content-blind. The app does not validate Google Maps, Apple Maps, Dashboard, Music, navigation state, or image content before using a frame. Whatever CarPlay is drawing is cropped with the user's persisted zoom/X/Y settings.

## Evidence from the v90.35.3.12 road test

The drive log separated transport from decode failure:

- MainVideo connected and decoded its first 800×480 frame.
- Roughly 12 seconds later, the app reported no decoded frame for >10 seconds while H.264 bytes were still arriving with essentially zero byte age.
- Only ~120 decoded frames had been published about 34 minutes later despite hundreds of MB of H.264 traffic.
- A later reconnect immediately produced a large decoded-frame burst.

That signature is not a crop/render failure. It means compressed transport remained alive while the decode/live-edge path stopped yielding current images and could later catch up stale data.

## iOS decoder changes

`U2WMainVideoClient` now prioritizes current-frame behavior:

1. **Access-unit assembly instead of slice-as-frame submission.** Annex-B VCL slices are grouped into one H.264 picture using AUD NALs when present and `first_mb_in_slice` boundaries otherwise.
2. **No hidden asynchronous VideoToolbox backlog.** One complete access unit is submitted synchronously. Downstream rendering has a single-frame mailbox; a newer image replaces the previous image instead of queueing video history.
3. **Fresh IDR required after decoder reset.** A damaged/interrupted generation cannot continue from dependent P/B pictures after a hard reset.
4. **First-frame watchdog fixed.** Fresh H.264 bytes without even one decoded image now trigger recovery; v90.35.3.12's watchdog could wait forever when `lastDecodedFrameAt` had never been set.
5. **Faster recovery.** Fresh-byte/no-image stalls trigger at 3 s with a 4 s reconnect cooldown. True source silence retains a longer 12 s allowance.
6. **Diagnostic separation.** `U2W VIDEO WATCH` reports freshness recovery and `U2W VIDEO DEC` reports decoder session/access-unit state.

The decoder may publish up to 15 newest images/s internally, but the physical HUD composition loop is deliberately left at **200 ms / 5 fps** for this reliability build.

## U2W v8.17 generation guard

v8.16 detected a new rolling-file generation only when the reopened file had become shorter than the old byte position. A replacement generation can be truncated and then regrow beyond that old position before the CGI reopens it; in that case the same numeric offset is no longer the same stream location.

v8.17 saves a short tail fingerprint before EOF. When the pathname is reopened, the old offset is reused only if the preceding bytes still match. Otherwise it immediately scans the new generation and seeds the client from the newest SPS/PPS + IDR. This removes the ambiguous size-only rollover case while preserving normal append performance.

## 5 fps vs faster rates

The 5 fps HUD rate is retained as the road-test baseline. It is not a network-bandwidth ceiling: typical 480×240 JPEG frames in the recent drive were roughly 13–15 KB, so 5 fps is only on the order of 65–75 KB/s and 10 fps would still be modest. The unknown is sustained iPhone SwiftUI/JPEG rendering plus the physical HUD MJPEG decoder/render path, not Wi-Fi throughput.

If this build survives a normal drive without a frozen center image, a later revision can expose 5/8/10 fps while keeping the same latest-frame-wins behavior. Raising the rate before fixing source/decode freshness would only make the failure harder to isolate.

## Right widget customization

The existing street, maneuver-arrow, distance, lane, and ETA size controls remain and their useful ranges are broadened. Three persisted vertical-gap controls are added:

- Street → maneuver
- Maneuver → lanes
- Lanes → ETA

The maneuver arrow and lane row also reserve additional layout height when enlarged so scale changes do not immediately overlap adjacent blocks.

## Intentionally unchanged

- Route Guidance parsing/delivery
- Now Playing integration
- GPS speed and speed-limit logic
- mode-6 JPEG relay and proven HUD STA sequencing
- mode 6 → mode 4 STA persistence diagnostic
- finalized ambient-light behavior
- OBD diagnostic parser (its malformed-chunk issue is left for a separate change)

# v90.35.3.15 + U2W v8.19 — Safe MainVideo, route inactive hold, OBD probe accessibility

This release follows the September 15 rollback road test. The adapter was stable again on the v8.11 exporter + v8.17 streamer, while MainVideo published frames #1→150 near the beginning, then only isolated #225 and #300 frames much later. The rolling stream also contained repeated multi-kilobyte false SPS/PPS candidates. The physical HUD JPEG relay remained alive, so the failure is upstream MainVideo parsing/decoder continuity rather than the KivicCast relay.

## Adapter

U2W v8.19 replaces only the MainVideo HTTP CGI streamer. It keeps the stable v8.11 AppleCarPlay exporter completely unchanged. No preload shim is added and no AppleCarPlay I/O function is intercepted. The streamer validates 800×480 H.264 SPS/PPS/slices and strips false Annex-B markers before bytes reach iOS.

## iOS MainVideo

The app now treats v8.19 as a sanitized stream and avoids the previous short reconnect loop. Decoder-stall recovery is 15 s, source silence is 30 s, and automatic reseeds are rate-limited to 30 s. Accepted SPS/PPS are further bounded to 256 bytes.

## Route Guidance

A decoded state-0 sample is no longer accepted after only two 750 ms polls. An established route must remain continuously inactive for 5 seconds before the app releases navigation ownership. Active guidance cancels the timer immediately. Existing 90 s transport and 180 s reachable-malformed JSON holdovers remain.

## OBD road-test probe

The 12-second native OBD speed probe no longer requires `obd.connected` before the Start button is enabled. With Map Mode active, pressing Start requests the HUD-side OBD connection if needed and waits up to 20 seconds. Once connection confirmation arrives, the existing two-phase 6 s + 6 s probe starts automatically. No production OBD speed source is enabled.

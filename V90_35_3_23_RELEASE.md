# v90.35.3.23 release notes

This revision is based on the 2026-09-19 parked and road-test evidence. U2W v8.23 successfully delivered a fresh SPS/PPS/IDR and real 800×480 CarPlay frames to the iPhone, while the dedicated TCP relay remained LIVE during later freezes. The remaining MainVideo failure was decoder-side: decoded output could stop while H.264 bytes remained fresh and `VTDecompressionSessionDecodeFrame` still returned `noErr`, and later VideoToolbox returned `-12903` (invalid session). This release therefore keeps U2W v8.23 unchanged and hardens the iPhone decoder lifecycle.

## MainVideo decoder recovery
- `-12903` is treated as a fatal VideoToolbox session failure. The dead session is retired immediately instead of receiving thousands of additional pictures.
- A fresh-H.264 / stale-decoded-frame watchdog now treats a 3-second output stall as a decoder failure while preserving the TCP/15332 transport and sanitizer state.
- Output-callback failures are logged and can trigger the same bounded decoder recovery path.
- Recovery recreates VideoToolbox from the last validated SPS/PPS and waits for the next validated live IDR; it does not reconnect or replay a historical GOP.
- New VideoToolbox sessions are marked real-time to reduce hidden playback backlog.
- App foreground/background lifecycle is logged and foreground return proactively refreshes a decoder that may have been invalidated by iOS.
- Parked preflight no longer passes after two frames. It requires at least 30 frames plus 20 seconds of continuously fresh decoded output.

## Lane guidance cleanup
- The stock HUD can redraw its cached lane layer when a new maneuver packet is delivered. If the new maneuver owns no lane guidance, the app now sends an immediate post-maneuver lane clear plus a 150 ms generation-guarded settle clear.
- If a legitimate new lane event arrives before the settle clear, the pending clear is cancelled.
- The top live Map Mode preview no longer substitutes the synthetic `straight / straight / straight+right` lane placeholder. The separate customization demo remains populated for at-home styling.

## Ambient night → day latency
- A single Center/BLEDOM transport loss still preserves confirmed NIGHT.
- If Center and Dashboard are both stably OFF, the existing 0.75-second two-source consensus now commits DAY immediately instead of waiting for the 15-second Center-only absence fallback.
- HUD Auto Brightness OFF and the Door night→day brightness fade therefore begin as soon as corroborated BOTH-OFF is stable.

## Physical HUD Map Mode join recovery
- The 2026-09-19 road test also isolated a separate final-hop problem: the iPhone could keep rendering and feeding U2W while the stock HUD stayed in Wi-Fi STA `status=4 / Address search timeout`, so the current HUD MJPEG viewer never attached.
- A valid HUD `192.168.50.x` address on stock status 4 or 6 is now treated as a soft link only for current-session viewer verification; success still requires the session-scoped HUD client + live-frame markers, so this cannot falsely declare Map Mode ready.
- If the initial `mode 6 → credentials → status → one credential refresh` sequence still has no link, the app performs exactly one bounded automatic join recreation: `mode 4 → mode 6 → credentials`, followed by two status probes. There is no repeating mode-6 loop.
- The existing current-session viewer recovery remains separate and bounded. This means the app can recover both a stalled STA join and a joined STA whose current KivicCast viewer did not attach.

## Adapter compatibility
This app release continues to use **U2W v8.23 Live-IDR Relay unchanged**. No adapter reflash is required when updating from v90.35.3.22.1.

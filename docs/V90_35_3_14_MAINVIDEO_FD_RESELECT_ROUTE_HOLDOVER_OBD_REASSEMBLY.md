# v90.35.3.14 + U2W v8.18

This release is a field-stabilization update on top of **v90.35.3.13.3**. The 3-preset Map Mode designer, including the one-time import of the user's pre-designer layout into Preset 1, is preserved unchanged.

## 1. MainVideo: adapter-side FD reselection

U2W v8.18 replaces the v8.11 MainVideo preload shim. The previous exporter selected a numeric fd and did not observe its lifetime. v8.18 hooks `close()` and promotes an fd only after a plausible Annex-B SPS/PPS/IDR bootstrap. It also invalidates a selected fd after repeated oversized false parameter sets or prolonged output without plausible H.264.

The v8.17 latest-generation HTTP streamer remains installed and unchanged.

## 2. Route Guidance continuity

The app now distinguishes two temporary Route Guidance failures:

- network/HTTP failure: retain the last active route for up to 90 seconds;
- reachable HTTP-200 response with malformed JSON: retain the last active route for up to 180 seconds.

A successfully decoded inactive route remains authoritative through the existing two-sample confirmation path. This specifically prevents transient malformed CGI publications from dropping an otherwise active Google Maps route to Freeride.

## 3. HUD OBD diagnostic reassembly

HUD diagnostic ZIP packets can span multiple BLE notifications while ordinary short HUD events arrive between continuation notifications. A dedicated notification-aware diagnostic collector now keeps the large diagnostic frame open across those interleaved events while allowing the ordinary events to continue through the normal protocol parser.

Raw OBD forensic bytes are still captured before parser-side duplicate suppression/reassembly. This remains an investigation feature; **no direct OBD vehicle speed source is claimed in this release** and no new speed-limit warning visual is enabled yet.

## Preserved behavior

- Map Mode physical composition remains 480×240 at 5 FPS.
- MainVideo center crop remains content-blind.
- Three Map Mode design presets and the imported current-layout Preset 1 remain intact.
- Existing navigation/lane/ETA rendering outside the holdover change is unchanged.
- Existing ambient-light behavior is unchanged.
- No speed-limit warning redesign is included yet.

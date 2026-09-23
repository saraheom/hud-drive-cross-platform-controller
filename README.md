# HUD Controller v90.35.3.24.8 + U2W v8.27 — lightweight live-edge MainVideo + OBD diagnostic ZIP reconstruction

This paired release replaces v8.26's large persistent-GOP replay/cache with a lightweight live-edge relay that waits on one persistent TCP session for the next validated live IDR. It also adds physical-HUD STA/viewer fail-safe recovery and reconstructs the HUD's chunked binary diagnostic archive for the next OBD-speed investigation. **Ambient lighting and the Door speed-warning animation are unchanged.**

**Flash U2W v8.27 for this release.** Use 10 FPS for the first validation. See `V90_35_3_24_8_RELEASE.md` and `V90_35_3_24_8_BUILD_VERIFY.txt`.

---

# HUD Controller v90.35.3.24.7 + U2W v8.26 — deterministic MainVideo bootstrap + HUD-internal OBD probe v4

This paired release keeps the proven v8.11 AppleCarPlay MainVideo capture and v8.15.1 HUD JPEG relay unchanged. U2W v8.26 preserves validated H.264 codec state and a disk-backed current-GOP recovery bridge across ordinary v8.11 rolling-file rotations, while the iOS client suppresses reconnect churn during intentional bootstrap waits and adds startup decoder hysteresis so the first decoded frame cannot be reset by the stale-output watchdog.

For OBD speed, the prior phone-facing v3 regression probe remains available, but the new v4 path moves deeper: it stimulates the HUD's stock hidden `OBD_DRIVING_VELOCITY` item during a 90-second road phase, then requests the HUD's own recent `LOG_CATEGORY_OBD` diagnostic files while parked for offline inspection of `010D`/`410D`, ELM `AT` traffic, internal speed values, or other stock OBD-service clues. It does not open a second OBD connection and does not replace visible GPS speed.

**Flash U2W v8.26 for this release.** For the first road test, use 10 FPS and start the OBD v4 road phase while parked. See `V90_35_3_24_7_RELEASE.md` and `V90_35_3_24_7_BUILD_VERIFY.txt`.

---

# HUD Controller v90.35.3.24.6.1 + U2W v8.25 — validated-GOP recovery + deep OBD speed probe v3

This app-only follow-up keeps the v90.35.3.24.6 MainVideo/v8.25 recovery code unchanged and adds a deeper 90-second OBD road probe for the same commute. The v3 probe records bounded HUD→iPhone RX frames in memory, correlates changing u8/u16/u32/BCD fields against simultaneous GPS using scale/offset regression and ±2-second lag, explicitly scans for binary `41 0D` and ASCII `410D` responses, and saves a shareable text report. It never opens a second OBD connection and never sends raw ELM/PID requests. While Map Mode is active it periodically reasserts the stock hidden `OBD_DRIVING_VELOCITY` item behind the full-screen JPEG so the visible GPS speed is unchanged.

Use the **same U2W v8.25 image** as v90.35.3.24.6; no new adapter firmware was built for .24.6.1. After the 90-second probe, the normal HUD log contains `OBD DEEP SUMMARY`, `OBD DEEP CANDIDATE`, and (if found) `OBD DEEP PID410D`. The existing parked **Request latest HUD OBD logs** tool remains available as a second forensic path. See `V90_35_3_24_6_1_RELEASE.md`.

---

# HUD Controller v90.35.3.24.6 + U2W v8.25 — validated-GOP recovery

This is a **paired app + adapter update** based on the 2026-09-21 evening drive. v8.25 keeps the stable v8.11 AppleCarPlay MainVideo exporter intact but replaces v8.24’s fragile in-memory recent-anchor recovery with a scan for the newest validated 800×480 SPS/PPS/IDR GOP in the bounded v8.11 rolling file. The iOS app understands the new diagnostics and retains the bounded one-reseed decoder policy from v90.35.3.24.5.

**U2W v8.25 must be flashed for this release.** For the first road validation, use 10 FPS; the 15 FPS setting remains available as a probe. OBD probe v2 remains diagnostic-only, and ambient-light production behavior is unchanged from v90.35.3.24.5. See `V90_35_3_24_6_RELEASE.md`.

---

# HUD Controller v90.35.3.24.5 — bounded MainVideo recovery + FPS/OBD probes

This is an **app-only** follow-up to the 2026-09-21 drive. MainVideo ran correctly for several minutes, then VideoToolbox `-8969` entered repeated recent-anchor reconnects even though H.264 bytes remained fresh. The new recovery policy allows one bounded recent-anchor reseed per stall episode; if it fails before producing a frame, the iPhone keeps TCP alive and waits for a genuinely new live IDR. A successful frame resets the reseed budget.

Map Mode now has a 5/8/10/12/15 fps HUD-output probe with actual send-rate and JPEG-throughput diagnostics. A separate 45-second OBD speed probe v2 reports standard PID `0x0D` support and scores hidden HUD `OBD_DRIVING_VELOCITY` traffic against GPS without changing the visible GPS speed or full-screen Map Mode.

**U2W v8.24 is unchanged. Do not reflash the adapter for this release.** Ambient-light production behavior is also unchanged from v90.35.3.24.4. See `V90_35_3_24_5_RELEASE.md`.

---

# HUD Controller v90.35.3.24.3 — physical HUD stale-lane renderer reset

This app-only release carries forward **v90.35.3.24.2 dual `U2WH2642` / `U2WH2643` MainVideo compatibility** and adds a generation-guarded physical-HUD lane reset. A 2026-09-20 field log proved the app preview cleared and three native empty-lane packets were transmitted while the HUD retained the old lane graphic once. The new path recreates the stock Navigation widget after a real lane payload ends, re-sends the current maneuver, and finishes with another empty-lane packet. New lane data cancels the reset before it can erase fresh guidance.

**No U2W reflash is required from v8.24.** See `V90_35_3_24_3_RELEASE.md` and `V90_35_3_24_3_BUILD_VERIFY.txt`.

---

# HUD Controller v90.35.3.24 — recent-IDR bootstrap + software decode + Center-only DAY guard

This release pairs the app with **U2W v8.24**. It closes the observed IDR-before-client startup race using a bounded 4 MiB recent SPS/PPS+IDR anchor, starts MainVideo predecode earlier in the car session, prefers software VideoToolbox decoding for the 800×480 navigation surface, and reconnects hard decoder recovery to the recent anchor. Ambient NIGHT→DAY is now Center/BLEDOM-only with a 1.0-second return guard; Dashboard no longer delays DAY.

The already-collected H.264 capture was replayed offline for both client-before-IDR and client-after-IDR orderings. Bounded bootstrap outputs through +3 MiB decoded as 800×480 / 514 frames with zero ffprobe errors. See `V90_35_3_24_CAPTURE_VALIDATION.md`, `V90_35_3_24_RELEASE.md`, and `V90_35_3_24_BUILD_VERIFY.txt`.

**U2W v8.24 must be flashed for this app release.**

---

# HUD Controller v90.35.3.23 — MainVideo fatal recovery + lane clear + fast DAY transition


> **v90.35.3.23.1 CI alignment:** adds the missing private `emitDecoderState()` worker helper required by the v90.35.3.23 recovery paths. Runtime behavior and U2W v8.23 are unchanged.

This release keeps **U2W v8.23 unchanged** and addresses the failures isolated in the 2026-09-19 parked/road tests. The dedicated adapter relay was confirmed healthy and delivered real 800×480 CarPlay frames; the remaining map freeze was decoder-side. v90.35.3.23 adds bounded VideoToolbox recovery for silent output stalls and fatal `-12903` sessions, fixes stale native HUD lane layers after a maneuver without lanes, removes synthetic lanes from the top live preview, and shortens corroborated night→day lighting latency.

Main changes:
- Fresh H.264 with no decoded image for 3 seconds is treated as a **decoder-output stall**, while TCP/15332 remains connected.
- VideoToolbox `-12903` is treated as a fatal session error and immediately enters bounded decoder recovery instead of receiving thousands of failed frames.
- Output-callback failures are now visible in diagnostics and feed the same recovery path.
- Decoder recovery reuses the last validated SPS/PPS and resumes at the next validated live IDR; there is still **no historical GOP replay**.
- New VideoToolbox sessions are configured for real-time decode.
- Parked preflight requires **20 seconds of continuously advancing frames**, not just the first two frames.
- Foreground/background lifecycle is tied into MainVideo recovery diagnostics.
- Native Navigation Mode lane state gets a post-maneuver clear when the new maneuver owns no lanes, with a generation-guarded 150 ms settle clear.
- The top live Map Mode preview no longer displays the hard-coded three-lane placeholder when live lane data is absent. The customization demo remains populated.
- Stable Dashboard+Center BOTH-OFF commits DAY after the existing 0.75-second consensus instead of waiting ~15 seconds; a single Center disconnect still latches NIGHT.
- Physical Map Mode join is also hardened: a stalled HUD STA association gets one bounded automatic `mode 4 → mode 6 → credentials` recreation, and status 4/6 with a valid HUD DHCP address can advance to session-scoped viewer verification without being treated as success by itself.

**No U2W reflash is required from v8.23.** See `V90_35_3_23_RELEASE.md` and `V90_35_3_23_BUILD_VERIFY.txt`.

---


---

# HUD Controller v90.35.3.21 — Dedicated H.264 relay + HUD cast watchdog

This release pairs the iOS app with **U2W v8.22**. It retires the v8.21 file-backed GOP/long-lived MainVideo CGI path after the 2026-09-18 drive showed decoder corruption around cache rewrites, Boa/CGI degradation, and a post-CarPlay-restart cache daemon that did not recover.

The new data path is:

`v8.11 MainVideo mirror → dedicated TCP/15332 H.264 relay → iPhone VideoToolbox → 480×240 Map Mode JPEG → U2W frame ingress → timeout-hardened HUD MJPEG sender`

Key changes:
- direct length-framed H.264 NAL transport on TCP/15332; continuous video no longer travels through Boa
- bounded in-process decoder-safe GOP across v8.11 pathname rotations
- continuous iPhone predecode from HUD BLE transport-ready
- automatic iPhone→U2W JPEG ingress reconnect
- timeout-hardened final U2W→HUD MJPEG socket so a stale HUD viewer cannot block the entire speed/map/maneuver composite indefinitely
- `MAP RENDER HEARTBEAT` diagnostics to isolate future freezes
- no AppleCarPlay hook/restart, no Route Guidance change, no Now Playing change
- lane graphics and large maneuver arrow are unchanged from v90.35.3.20.1

See `V90_35_3_21_BUILD_VERIFY.txt` and `u2w/v8.22_DedicatedH264Relay/BUILD_VERIFY.txt`.

---

# HUD Controller v90.35.3.20.1 — CI alignment only

This is runtime-identical to v90.35.3.20. GitHub Actions built the app successfully and 299/300 XCTest cases passed; the sole failure was a stale v90.35.3.17 source-string guard that still expected the former long lane-arrow wording. The guard now validates the approved shorter Google-style lane geometry and shared combined-arrow body. U2W v8.21 is unchanged.

See `V90_35_3_20_1_BUILD_VERIFY.txt`.

---

# HUD Controller v90.35.3.20 — persistent MainVideo GOP cache + shorter lane guidance + empty idle Map Mode

This release is based on the 2026-09-17 afternoon road test. The v8.11 exporter continued receiving CarPlay MainVideo, but v8.20 could not open the HTTP stream whenever the current rolling generation contained only non-IDR P-slices. Returning Google Maps to its default map produced a fresh SPS/PPS/IDR and immediately restored live video. Repeated blocked MainVideo CGIs also correlated with a 106-second Route Guidance/Now Playing blackout.

## U2W v8.21 Persistent GOP Cache

`u2w/v8.21_PersistentGOPCache` leaves AppleCarPlay, the v8.11 exporter, Route Guidance, Now Playing, and the HUD JPEG relay untouched. A small standalone ARM daemon tails `/tmp/u2w_mainvideo_live.h264` continuously and preserves the latest decoder-safe `SPS + PPS + IDR + following slices` across exporter pathname rotations. New MainVideo clients read that cache instead of rescanning only the current rolling file.

- Cache start: `/cgi-bin/u2wvideo-cache-start.cgi`
- Cache diagnostics: `/cgi-bin/u2wvideo-cache-status.cgi`
- MainVideo: `/cgi-bin/u2wvideo-main-stream.cgi`
- If no decoder-safe GOP has been captured yet, MainVideo returns HTTP 503 with `Retry-After: 2` instead of blocking indefinitely.
- Stream CGIs self-terminate after about five seconds without cache growth, limiting orphaned Boa CGI accumulation after client cancellation.
- The iOS app warms the GOP cache when the HUD BLE transport becomes ready, before a route is likely to rotate the v8.11 file mid-GOP. The actual MainVideo HTTP stream remains Map-Mode-only.
- Diagnostics now show GOP-cache ready state, cache bytes, daemon pid, and active stream CGI count.

## Lane guidance

Only the compact lane-guidance glyphs are redesigned. The large turn-by-turn maneuver arrow remains unchanged. Lane arrows now use the approved shorter, more curved geometry, while straight+left/right turn-only guidance continues to draw the white turn path directly on top of the gray straight stem. CarPlay lane types remain source-derived from 0x5204 direction angles (`straight`, `right`, `straight+right`, `left`, `straight+left`) and lane recommendation state.

The existing Map Mode controls remain available, with a wider useful range:
- Lane arrow size: 60–170%
- Lane arrow thickness: 0.60–2.50×
- Lane spacing
- Inactive-lane gray
- Active-lane emphasis

## Empty idle Map Mode

When no live navigation route exists, Map Mode no longer fabricates the old sample route, maneuver, street, distance, or lane guidance. The center/right navigation regions stay empty until real CarPlay Route Guidance is active. Speed and a valid OSM speed-limit sign remain independent left-side vehicle information.

See `V90_35_3_20_BUILD_VERIFY.txt` and `u2w/v8.21_PersistentGOPCache/BUILD_VERIFY.txt`.

---

# v90.35.3.19.1 — CI-only lane-vector regression alignment

v90.35.3.19.1 changes no production runtime Swift from v90.35.3.19. The iOS 26 simulator build already succeeded; CI failed only because the older v90.35.3.17 lane regression expected the pre-v90.35.3.19 `func combined(right: Bool)` source signature. The test now recognizes the color-aware vector helper and the turn-only overlapping helper used by the approved lane-guidance design.

See `V90_35_3_19_1_BUILD_VERIFY.txt`.

---

# HUD Controller v90.35.3.18.1 — CI-only lane-vector test alignment

## v90.35.3.18.1 — no runtime changes

This revision is runtime-identical to v90.35.3.18. GitHub Actions compiled the iOS app and test target successfully, then found one stale XCTest assertion from the former SF-Symbol lane renderer. The test expected `symbolWeight(settings.laneArrowThickness)`, while v90.35.3.18 intentionally moved lane thickness into the custom `LaneGuidanceGlyph` vector `lineWidth`. The regression guard now validates that vector contract instead. MainVideo recovery, U2W v8.20 validated-GOP bootstrap, lane geometry, two-line street names, ambient lighting, navigation, and OBD behavior are unchanged.

See `V90_35_3_18_1_BUILD_VERIFY.txt`.

---

# HUD Controller v90.35.3.18 — MainVideo recovery + validated U2W GOP bootstrap + vector lane graphics

## v90.35.3.18 — commute-driven MainVideo recovery and Map Mode UI refinement

This release is based on the 2026-09-17 commute evidence. Raw U2W MainVideo bytes and valid H.264 P-slices continued after one VideoToolbox decode error, but v90.35.3.17 immediately forced `needsIDR=true`, leaving the image frozen until navigation ended and CarPlay emitted a genuine new SPS/PPS/IDR sequence. Cellular state was not causal.

### Live MainVideo recovery

- One isolated VideoToolbox decode error no longer forces an IDR reset. The decoder keeps its current session and continues submitting validated pictures.
- Only repeated **consecutive** decode failures trigger a decoder-session rebuild from the last-known-good SPS/PPS.
- The 20-second fresh-bytes/stale-image watchdog is now diagnostic-only; it no longer performs the destructive local reset that previously made recovery impossible.
- If raw bytes remain fresh but no decoded image has returned for 90 seconds, the app performs one rate-limited HTTP live-edge reseed.
- MainVideo response logging now records the U2W streamer's `X-U2W-Streamer` header.

### U2W v8.20 validated-GOP bootstrap

`u2w/v8.20_ValidatedGOPBootstrap` is included with install/uninstall images. It changes only the MainVideo CGI streamer. The stable v8.11 AppleCarPlay exporter, Route Guidance, Now Playing, and HUD JPEG relay are untouched.

The v8.20 bootstrap keeps the v8.17 generation guard but validates the candidate SPS/PPS/IDR using NAL length, forbidden/reference bits, SPS profile, ordering, and proximity before selecting the newest decoder-safe GOP. This reduces the chance that unrelated bytes containing accidental Annex-B-looking patterns seed a reconnect. The uninstall image restores the exact v8.17 streamer.

### Lane guidance graphics

- Replaces stacked SF Symbols with custom thin/long vector lane arrows.
- Straight+left and straight+right now share one vertical body and branch around mid-height, keeping their arrowheads separated.
- Existing centered contiguous lane packing is retained, including the best-four-lane window for 5+ lane roads.
- Merge-left, merge-right, and merge-ahead maneuver graphics are rendered when the source maneuver description explicitly says `merge`; lane metadata itself is not guessed to be merge because 0x5204 provides direction angles but no merge semantic.

### Turning street name

The upcoming street name always owns a fixed two-line region. Short names use only the top line and keep the second line empty; longer names wrap to two centered lines instead of clipping at the right edge. The rest of the right-side layout therefore remains stable as street-name length changes.

### OBD item-10 experiment

The item-10 Map Mode visual experiment is retired from the UI/runtime path in this build. The road test confirmed the command was sent while OBD was connected but the native HUD item did not composite above the mode-6/KivicCast image. No new OBD-speed experiment is included in v90.35.3.18.

---

# HUD Controller v90.35.3.17 — persistent item-10 OBD test + iPhone network trace + lane rendering fixes

## v90.35.3.17 — item-10 OBD toggle, iPhone network trace, speed-limit/lane UI fixes

- Converts the live Map Mode `OBD_DRIVING_VELOCITY` (`itemIndex=10`) road test from a 12-second button into a persistent toggle. The control is now its own card outside the collapsible Map Mode image-customization block. If armed while Map Mode is off, it starts automatically on the next live relay session.
- Adds Map-Mode-only `NWPathMonitor` logging for default, Wi-Fi, and cellular paths. `IPHONE NETWORK` log lines include path changes plus MainVideo byte/frame age and H.264 counters so cellular/default-route transitions can be correlated with live-map stalls. The diagnostics card also shows the current default/Wi-Fi/cellular path state.
- The custom speed-limit sign is rendered only when the OSM-derived/held display limit is greater than zero. The sign slot remains reserved when unavailable, so the speed number does not jump or re-center vertically.
- Lane arrows are packed contiguously and centered instead of stretching to the edges. For more than four lanes, Map Mode selects the best readable four-lane window around the recommended lane cluster; if no lane is recommended, it uses the center four.
- Native lane types `3` (straight + right) and `5` (straight + left) now render as combined straight/turn glyphs rather than diagonal arrows.


This is an **app-first stability release** paired with the proven **U2W v8.11 MainVideo exporter + v8.17 LatestFrame streamer**. **Do not keep U2W v8.19 installed for road use.** The v8.19 standalone CGI filter was isolated from AppleCarPlay, but field testing showed repeated MainVideo CGI timeouts, whole-adapter lag, and an adapter/CarPlay restart. Use the bundled v8.19 uninstall image to restore the exact v8.17 streamer; the v8.11 exporter remains untouched.

The expensive H.264 validation now runs on the iPhone. Raw v8.17 bytes are syntax-checked for a real **800×480** SPS/PPS/slice relationship before VideoToolbox sees them. Dirty bytes trigger only a local decoder resync; they no longer cause repeated HTTP/CGI reconnects. A transport reconnect is allowed only after **60 seconds of true source silence**, and retries back off for 5 seconds after actual HTTP errors. MainVideo itself is now **strictly Map-Mode-only**: normal Navigation/Freeride does not open the video endpoint at all.

The 12-second OBD probe remains available. Based on the 2026-09-16 field test, probe cleanup no longer clears the stock OBD custom slot immediately; it restores fullscreen/KeepAlive while leaving the slot hidden, then performs one delayed OBD health reassert if needed. The previous probe data still does not identify a trustworthy production OBD vehicle-speed value, so no OBD-based speed-warning feature is enabled.

See `docs/V90_35_3_16_IPHONE_MAINVIDEO_FILTER.md` and `V90_35_3_16_BUILD_VERIFY.txt`.

---

# HUD Controller v90.35.3.15 — Safe MainVideo + route inactive hold + accessible OBD probe

This release keeps the stable **v8.11 MainVideo exporter** and replaces only the v8.17 HTTP streamer with **U2W v8.19 Safe MainVideo Filter**. The v8.18 AppleCarPlay fd-reselection preload is intentionally not used. v8.19 runs only as a standalone Boa CGI reader of `/tmp/u2w_mainvideo_live.h264`; it does not hook or restart AppleCarPlay.

The iOS app reduces MainVideo reseed pressure (15 s decoder stall, 30 s source silence, 30 s cooldown), requires five seconds of continuous decoded Route Guidance inactivity before returning to Freeride, and lets the 12-second OBD probe request/wait for HUD-side OBD connection instead of leaving its button disabled. The three Map Mode presets/designer, 5 fps HUD relay, media, lane behavior, and ambient-light logic remain otherwise unchanged.

See `docs/V90_35_3_15_SAFE_MAINVIDEO_ROUTE_OBD.md`, `V90_35_3_15_BUILD_VERIFY.txt`, and `u2w/v8.19_SafeMainVideoFilter/README.md`.

---

# HUD Controller v90.35.3.14.1 — CI alignment only

The iOS 26 GitHub Actions build for v90.35.3.14 compiled successfully and ran 287 XCTest cases. One legacy source-string regression assertion still expected the pre-v90.35.3.14 45-second Route Guidance transport holdover, while the production v90.35.3.14 implementation intentionally uses a 90-second network/HTTP-failure holdover and a separate 180-second holdover for reachable HTTP-200 responses with temporarily malformed JSON.

This alignment revision updates only `V903539ReliabilityTests.testRouteGuidanceTransportHoldoverDoesNotImmediatelyDropHUD` to assert the intentional 90 s / 180 s policy. No file under `ios/HUDController/` changed. MainVideo FD reselection, Route Guidance runtime behavior, OBD diagnostic reassembly, the three Map Mode presets/designer, navigation/lane behavior, media, ambient lighting, and physical 5 fps relay are byte-for-byte unchanged from v90.35.3.14. The paired adapter remains **U2W v8.18**; no U2W reflash is required.

See `V90_35_3_14_1_CI_ALIGNMENT.md`.

---

# HUD Controller v90.35.3.14 — MainVideo FD reselection + Route Guidance holdover + OBD diagnostic reassembly

This release builds directly on **v90.35.3.13.3** and preserves the three-preset Map Mode designer, including the one-time migration of the existing pre-designer layout into Preset 1. It is paired with **U2W v8.18 MainVideo FD Reselection**.

The iOS app now keeps an active Google Maps/Apple Maps route through bounded temporary Route Guidance transport or malformed-JSON outages instead of immediately dropping the physical HUD to Freeride. The HUD OBD diagnostic path now has a notification-aware large-frame reassembler that can keep a diagnostic frame open while ordinary HUD events are interleaved. No production OBD vehicle-speed source is enabled yet.

U2W v8.18 replaces only the MainVideo preload exporter shim and its status CGI. It validates a candidate fd using an Annex-B SPS/PPS/IDR bootstrap, invalidates the selected fd when it is closed or begins carrying implausible/non-H.264 content, and can promote a newly validated fd. The existing **v8.17 latest-frame HTTP streamer remains installed and unchanged**. A full Carlinkit power cycle is required after installing or uninstalling v8.18.

See `docs/V90_35_3_14_MAINVIDEO_FD_RESELECT_ROUTE_HOLDOVER_OBD_REASSEMBLY.md`, `V90_35_3_14_BUILD_VERIFY.txt`, and `u2w/v8.18_MainVideoFDReselect/README.md`.

---

# HUD Controller v90.35.3.13.1.1 — CI alignment only

This is the same runtime as **v90.35.3.13.1** and uses the same **U2W v8.17 LatestFrame** image. The GitHub Actions Xcode 26 build succeeded, but two legacy source-string XCTest assertions still expected the pre-v90.35.3.13 Map Mode section title and the old 10-second MainVideo watchdog constant. Those tests are now aligned with the intentional v90.35.3.13 behavior: **Right-side component size / spacing** and a **3-second decoder-stall watchdog** with a **12-second source-silence allowance**.

No files under `ios/HUDController/` were changed in this CI-alignment revision. MainVideo, OBD forensics, Route Guidance, ambient lighting, and the 5 fps HUD relay are byte-for-byte unchanged from v90.35.3.13.1. No U2W reflash is required.

See `V90_35_3_13_1_1_CI_ALIGNMENT.md`.

---

# HUD Controller v90.35.3.13.1 — OBD forensics + v90.35.3.13 live MainVideo

This is an **app-only** follow-up to v90.35.3.13. Keep **U2W v8.17 LatestFrame** installed; no adapter reflash is required. The content-blind CarPlay crop, latest-frame MainVideo decoder, and physical 5 fps HUD relay are unchanged.

The Vehicle tab now preserves a bounded raw HUD BLE capture before the stock diagnostic parser, reports the diagnostic categories actually returned by the HUD, logs detailed chunk framing/mismatch information, scans for PID `0x0D` / ELM signatures and GPS-correlated numeric candidates, and saves `HUD_OBD_RawBLE_<timestamp>.bin` when the transfer completes or **Stop & save raw** is pressed. The existing native `OBD_DRIVING_VELOCITY` probes also get a short forced `OBD PROBE RX` logging window. No production OBD speed decoding is enabled yet.

See `docs/V90_35_3_13_1_OBD_FORENSICS.md` and `V90_35_3_13_1_BUILD_VERIFY.txt`.

---

# HUD Controller v90.35.3.12 — U2W v8.16 live-edge map + HUD OBD diagnostic capture

This road-test build keeps the proven mode-6 JPEG relay, route/media fixes, ambient-light behavior, speed-limit sign customization, and mode 6 → mode 4 STA persistence test unchanged.

New in this revision:

- **U2W v8.16 MainVideo live-edge streamer:** each new HTTP connection seeds VideoToolbox with the latest SPS/PPS and newest IDR, then follows from that IDR rather than replaying byte zero. At EOF it reopens the pathname so exporter generation replacement cannot strand a stale file descriptor.
- **iOS MainVideo source diagnostics:** the emergency stale-frame watchdog is relaxed to 10 s with a 12 s cooldown and separately tracks incoming H.264 bytes vs decoded frames.
- **HUD-native OBD diagnostic download:** the Vehicle tab can request `LOG_CATEGORY_OBD` using the stock HUDWAY diagnostic packet protocol and reassemble the returned chunked ZIP for sharing. This does not open a second OBD connection.
- Existing **mode 6 → mode 4 Wi-Fi association test** remains available under Map Mode Status & diagnostics.

See `docs/V90_35_3_12_LIVE_EDGE_OBD_DIAGNOSTIC.md`.

---

# HUD Controller v90.35.3.11.1 — CI alignment only

This is the same production runtime as **v90.35.3.11**. GitHub Actions compiled the app successfully but one stale `SpeedUnitTests` assertion rejected the new passive OBD diagnostic help text because it contains the literal `km/h`. The test now verifies that actual GPS/speed-limit UI bindings remain mph while allowing diagnostic prose to mention both mph and km/h candidate encodings. No files under `ios/HUDController/` were changed. Paired adapter remains **U2W v8.15.1 No Known-Image Primer**.

See `V90_35_3_11_1_CI_ALIGNMENT.md`.

---

# HUD Controller v90.35.3.11 — road-test OBD trace + speed-sign tuning + STA persistence probe

Paired adapter remains **U2W v8.15.1 No Known-Image Primer**; no adapter-side changes are required for this app revision. v90.35.3.10.1 Map Mode streaming, live-map crop/fade controls, grayscale lane tuning, compact UI, navigation holdover, and finalized ambient-light behavior are retained.

For tomorrow's combined drive test, this revision adds three deliberately isolated diagnostics/customization features. First, passive **OBD speed protocol tracing** annotates HUD→iPhone BLE packets against simultaneous GPS mph/km/h without opening a second OBD connection or sending extra PID requests. `OBD TRACE`, `OBD TRACE RX`, and `OBD STATUS` log entries preserve raw payload bytes plus plausible u8/u16/u32/float candidates that track vehicle speed. A separate optional 12-second visual probe temporarily blanks the custom GPS speed and asks the HUD for stock `OBD_DRIVING_VELOCITY`; phase 1 leaves fullscreen untouched, and phase 2 briefly exposes the stock HUD layer.

Second, the Map Mode speed-limit sign now has persisted **Sign height** (80–200%) and **Number font size** (70–160%) controls. Width, white fill, black border, and black number remain fixed.

Third, a collapsed **Mode 6 → 4 Wi-Fi association test** keeps U2W/frame ingress running, switches only the HUD renderer to mode 4, and requests stock STA status at 1.5/3/6 seconds. A separate mode-6-only return button sends no SSID/password, allowing one drive to test whether the HUD's U2W association survives normal HUD mode.

See `docs/V90_35_3_11_ROAD_TEST_INSTRUMENTATION.md` and `V90_35_3_11_BUILD_VERIFY.txt`.

---

# HUD Controller v90.35.3.10.1 — compact Map Mode UI + visual calibration

Paired adapter update: **U2W v8.15.1 No Known-Image Primer**. This release keeps the v90.35.3.9.1 map-video/navigation/ambient reliability behavior and only refines Map Mode presentation, startup priming, and UI density.

New Map Mode controls: inactive lane arrows remain grayscale but their gray level is adjustable from dark to bright; selected/recommended lanes remain white. Center-map edge fade is independently adjustable horizontally and vertically. The custom speed-limit sign is reduced to a white rectangle with the black limit number only.

The normal Map Mode control surface is simplified to CarPlay-adapter Wi-Fi name/password plus one **Enable/Disable Map Mode** button. Relay/video diagnostics are collapsed by default. The legacy mode-5 control block is removed from the visible UI. All Map Mode image-calibration controls are grouped under one collapsed disclosure. Standard `HudDescription` explanatory blocks across the app now start collapsed while keeping their disclosure chevron.

The app prewarms one real 480×240 iPhone-rendered frame before entering HUD mode 6. Paired U2W v8.15.1 removes the old v8.13 known-image primer entirely: the HUD MJPEG connection waits for a valid live iPhone frame and primes the decoder with that live frame instead. If live input pauses, U2W holds the HUD's previous image rather than substituting the known test image.

The proven v90.35.3.9.1 ambient-light reconnect behavior is unchanged, including no software Power ON during normal headlight-powered Dashboard startup. OBD2-first speed remains deferred.

See `docs/V90_35_3_10_MAP_MODE_UI_REFINEMENT.md`, `V90_35_3_10_BUILD_VERIFY.txt`, and `u2w/v8.15.1_NoFallbackPrimer/README.md`.

---

# HUD Controller v90.35.3.9.1 — MapVideo / Navigation / targeted Dashboard reconnect recovery

This paired release uses **U2W v8.15** and keeps the v90.35.3.9 map-video and Route Guidance reliability fixes while narrowing the ambient-light change to the physical Dashboard reconnect problem. The previously finalized Center/day-night state machine is restored unchanged. Normal headlight OFF→ON cycles also keep the established **Already-On Minimal / no software Power ON** behavior so the old startup blink does not return.

The targeted ambient change is limited to Dashboard/BLEDIM reconnect timing: a fresh Dashboard GATT reconnect outside an active headlight cohort is held quiet through the normal 1.5-second controller boot settle, then gets a **brightness-only steady reassert**. If the strict Center+Dashboard headlight cohort opens during that settle, Dashboard is handed into the synchronized Breath instead. This also recovers an interrupted Breath that stranded Dashboard near 0% without sending Power ON or RGB. An explicit Power/RGB/brightness prime is reserved only for a deliberate **app-issued manual Power OFF → ON/Preview** recovery, where logical LED output is actually known to be off.

U2W v8.15 remains unchanged: rotation-safe MainVideo streaming, serialized Route Guidance/Now Playing JSON publication, and session-scoped HUD relay status/Stop→Start behavior. OBD2-first speed remains deferred.

See `docs/V90_35_3_9_1_RELIABILITY.md`, `V90_35_3_9_1_BUILD_VERIFY.txt`, and `u2w/v8.15_Reliability/README.md`.

---

# HUD Controller v90.35.3.8 — physical Map UI layout calibration

This app-only revision keeps the proven **v90.35.3.7 + U2W v8.14.3** live relay transport unchanged and adds the requested in-car visual calibration controls for the rendered 480×240 HUD frame. The normal start path remains mode 6 once → NISSAN68 credentials once → wait; no U2W reflash is required.

New persisted controls include bounded 2-pixel X/Y movement for the full left, center-map, and right widgets; maneuver-arrow size and boldness; turning-street and distance text scaling; lane-arrow size/boldness/spacing/active-lane emphasis; ETA/time-left scaling; and separate fine positioning for maneuver, lane guidance, and ETA/time-left. Reset controls are included for each calibration group. These controls update both the phone preview and the live JPEG sent through the U2W relay.

OBD2-first speed remains intentionally deferred for this car test. Route Guidance parsing, lane decoding, CarPlay MainVideo acquisition, BLE/U2W transport, and the 5 fps relay cadence are unchanged.

See `docs/V90_35_3_8_MAP_UI_LAYOUT_CALIBRATION.md` and `V90_35_3_8_BUILD_VERIFY.txt`.

---

# HUD Controller v90.35.3.7 — known-good mode-6 sequencing

This app-only relay stability revision keeps U2W v8.14.3 unchanged and restores the control ordering from the first successful physical HUD-as-STA test: send mode 6 once, send NISSAN68 credentials once, then wait. It deliberately does not send another mode-6 command when Wi-Fi status=1 arrives.

Why: the v90.35.3.6 field log showed a clean status=1 / 192.168.50.100 join, but every post-connect mode-6 viewer prime was followed by zero KivicCast discovery packets. The original v8.13 physical-image success did not use a post-connect mode-6 rewrite.

Changes:
- Start no longer bounces through mode 4 before the normal join.
- status=1 starts an 8-second read-only U2W discovery/client monitor; it does not rewrite mode 6.
- no automatic mode-6 retry occurs after link-up.
- `Retry HUD display` performs one controlled full viewer recreation (mode4 -> 900 ms -> mode6 -> 300 ms -> credentials) and is rate-limited to 10 seconds.
- U2W v8.14.3 remains the required adapter image.


---

# HUD Controller v90.35.3.6 — U2W live relay MJPEG stability

This paired release targets the first fully reproduced post-discovery failure. Field logs show the HUD reaches Wi-Fi status=1, emits repeated KivicCast discovery packets, and opens TCP/15330, while the iPhone continues uploading valid JPEG frames. v90.35.3.6 stops bouncing mode 6 after discovery has already succeeded and gives the HUD viewer a quiet HTTP settle window.

Use with U2W v8.14.3. The adapter-side relay is now SIGPIPE-safe, supports repeated HUD HTTP probes/reconnects, primes the HUD decoder with the exact known-good v8.13 JPEG, and then switches to live baseline 480x240 frames.

The Navigation tab stays green and the temporary Vehicle Speed Marker Probe UI remains removed.

---

# HUD Controller v90.35.3.5 — U2W live relay IP soft-connect recovery

This release keeps the v90.35.3.4 BLE nested-frame resynchronization, but removes the destructive empty-SSID STA reset that the latest field log showed can trap the HUD in stock status 6 ("Empty network").

Key field finding: the HUD can report status 6 while also returning a valid DHCP address such as `192.168.50.100`, and the U2W ARP table simultaneously contains both HUD and iPhone peers. v90.35.3.5 therefore treats a valid HUD IPv4 address as a usable STA link even when status 6 is reported, and proceeds to kick the KivicCast viewer/discovery path.

Fresh Start now uses:
`mode 4 -> short settle -> mode 6 -> NISSAN68 credentials`

It never sends empty SSID/password credentials during Start. `Retry HUD display` can also force the mode-6 viewer path when the BLE status is ambiguous.

U2W v8.14.2 remains the required adapter image; no adapter reflash is needed when upgrading from v90.35.3.4.

# HUD Controller v90.35.3.4 — STA reset + BLE frame resync (CI alignment)

# v90.35.3.3 — HUD STA clean-reset + BLE frame resynchronization

This release keeps the validated iPhone → U2W → HUD live-JPEG relay and targets the latest field failure where the HUD remained in Joining / Empty network even though U2W frame ingress was healthy.

The latest BLE log contained an interrupted firmware/version frame followed by a new Wi-Fi event STX before the first frame ended. The old parser could swallow that nested event. Since STX is escaped inside valid HUD payloads, v90.35.3.3 safely resynchronizes on an unescaped nested STX.

A fresh Start also performs a deterministic stock-style STA reset: mode 4 → empty STA credentials/security 0 → 1.8 s settle → mode 6 → fresh `NISSAN68` credentials/security 2. Reset-phase/stale EMPTY events are ignored so they cannot overwrite the new join attempt. One credentials-only refresh is allowed if status=1 is still absent.

**Adapter:** keep U2W v8.14.2 installed. No U2W reflash is required for this app revision.

---

# v90.35.3.2 — Post-association KivicCast discovery kick

Field logs from v90.35.3.1 showed that the HUD could receive `status=1 connected` with a valid `192.168.50.x` address while U2W saw **no UDP/15320 discovery at all**. The viewer was being launched in mode 6 before STA/DHCP had completed, so it could finish association after its one-shot discovery attempt had already failed. v90.35.3.2 therefore re-primes mode 6 only after the positive STA event, verifies the live MJPEG TCP connection through U2W status, and performs one bounded retry if necessary.

Repeated Start is now guarded in the app; use **Retry HUD display** instead of restarting the full relay. Stop restores mode 4 but deliberately preserves the HUD's saved STA credentials, avoiding the asynchronous `Empty network` status generated by the old credential-clear command. Pair this app with U2W v8.14.2, whose start CGI is idempotent and whose persistent discovery daemon responds on the dedicated KivicCast discovery port without tearing down healthy relay processes.

# v90.35.3.1 — Live iPhone → U2W → HUD frame relay stability

v90.35.3.1 retains the v90.35.3 live relay architecture and stabilizes it. v90.35.3 originally promoted the successful v8.13 HUD-as-STA home test into the preferred physical Map Mode transport. The iPhone stays connected to the Carlinkit/U2W AP, the HUD joins that same AP using stock `IOS_KIVICCAST_STA_MODE` (mode 6), and the app continuously renders the existing 480×240 custom HUD composition at 5 fps. Each JPEG is sent over a persistent TCP connection to U2W v8.14.1 on `192.168.50.2:15331`; U2W then serves the latest frame to the HUD through the already-validated KivicCast discovery/MJPEG path on UDP 15320 / TCP 15330.

Unlike the legacy mode-5 experiment, v90.35.3 does **not** stop U2W MainVideo, Route Guidance, lane, or Now Playing polling and does **not** switch the iPhone to HUDWAY Wi-Fi. The center map therefore uses `mainVideo.latestFrame` live rather than a frozen pre-handoff image. The existing manual crop/zoom controls remain in place for Dashboard geometry calibration.

The v8.13 physical result established that stock HUD Wi-Fi status `1` means connected even when the optional address field is omitted. v90.35.3 corrects that parser behavior.

Paired **U2W v8.14** leaves `wlan0`, hostapd, DHCP, SSID, password and channel unchanged. It preserves the v8.8 Route Guidance exporter and v8.11 MainVideo exporter. Before the first iPhone JPEG arrives it serves the known v8.13 test image as a fallback.

---

# v90.35.2.1 — HUD-as-STA → U2W home diagnostic (CI alignment)

v90.35.2.1 is runtime-identical to v90.35.2 and aligns one stale XCTest with the intentional removal of the temporary Speed Marker Probe UI. v90.35.2 adds a no-CarPlay home diagnostic for the shared-network architecture. The iPhone stays connected to the existing U2W/Carlinkit AP while the HUD is commanded over BLE into stock `IOS_KIVICCAST_STA_MODE` (mode 6) and receives the U2W SSID/password using the recovered `WifiSTAModeCommandPacket`. The app now parses the returned `WifiSTAStatusEventPacket`, including status, reason and assigned IP.

Paired **U2W v8.13** leaves the normal U2W AP unchanged and serves a known 480×240 KivicCast image directly from `192.168.50.2`. This test therefore determines whether the HUD can join the same U2W AP as a second station and pull the cast stream without moving the iPhone to HUDWAY Wi-Fi.

Requested UI cleanup is included: Navigation uses the original green app accent again, and the temporary Vehicle **Speed Marker Probe** card is removed from the visible UI. Production speed/speed-limit behavior is unchanged.

See `docs/V90_35_2_HUD_STA_U2W_HOME_DIAGNOSTIC.md`.

---

# v90.35.1.1 — CI regression alignment for OFF-only time/weather rehydration

The first v90.35.1 GitHub Actions run compiled successfully and reached the full unit-test phase. It executed 266 tests; the only failures were three stale assertions in `V903416TimeWeatherColdOffSpeedGaugeProbeTests` that still expected the removed v90.34.16 cold-session ON → OFF edge. v90.35 intentionally changed that behavior to an OFF-only delayed reassert after the September 11 field test showed the transient ON could leave the panel visible.

This hotfix updates that legacy test to enforce the current OFF-only invariant. **No runtime Swift source, live U2W MainVideo behavior, Map Mode behavior, or U2W v8.11 image changes.**

See `V90_35_1_1_BUILD_VERIFY.txt`.


---


# v90.35.1 — live U2W MainVideo map crop + source-theme filters

v90.35.1 pairs with **U2W Main CarPlay Video Live Exporter v8.11**. The adapter now passively exposes the already-proven 800×480 MainVideo H.264 stream at `192.168.50.2`; the iOS app decodes it with VideoToolbox and uses the latest real CarPlay frame as the center Map Mode source. There is still no ScreenCaptureKit/OCR fallback.

The Map Mode preview now shows a **Live U2W map source** status/card with decoded frame count and source resolution. The center source supports three appearance modes: **Follow source** leaves Google Maps / Apple Maps / Waze pixels unchanged, including their own light/dark theme; **Dark HUD** and **Light HUD** are optional post-processing filters applied to those same pixels. Map zoom and X/Y crop are independently adjustable and persisted; defaults are tuned from the 800×480 Google Maps frame recovered in the September 10 v8.10 dump.

The approved left/right widgets remain unchanged: U.S. rectangular speed-limit sign, turning street above maneuver, distance, live lanes, ETA and time-left, with independent left/center/right scaling and per-component show/hide controls. The native OBD Driving Velocity overlay experiment is also retained.

**Network boundary:** while the iPhone is on U2W Wi-Fi, the in-app map preview is genuinely live. The current physical KivicCast test still requires moving the iPhone to the HUDWAY mode-5 AP, so enabling physical Map Mode freezes the latest decoded U2W frame and semantic route before that handoff. A continuously live physical-HUD map still depends on separately validating the HUD-as-U2W-STA/shared-network path. The UI and logs state this explicitly rather than presenting the frozen frame as live.

See `docs/V90_35_1_LIVE_U2W_MAINVIDEO_MAP_CROP.md` and `u2w/v8.11_MainVideoLive/README.md`.

---

# v90.35 — Custom Map Mode cast + OBD-speed overlay probe + per-component layout

v90.35 converts the v90.34.17 Map Video Display preview into a bounded physical-HUD test. The custom 480×240 renderer uses the approved HUD-safe **left / center / right** composition: U.S.-style speed/speed-limit on the left, sparse map in the center, and turning street / maneuver / distance / lane guidance / ETA / time-left on the right. Left, center and right scale independently, and every individual component can be shown or hidden.

The new **Enable Map Mode on HUD** control starts the recovered stock KivicCast mode-5 AP plus an iPhone UDP discovery / HTTP MJPEG responder. Because the iPhone cannot remain on Carlinkit and HUDWAY Wi-Fi simultaneously, v90.35 freezes the last live U2W semantic route before the handoff and resumes normal U2W polling after Map Mode is disabled. The current center map is still the custom schematic: U2W v8.10 proved main CarPlay video exists, but no app-friendly live frame endpoint has been wired yet. **Follow source** is retained as the production target for that later live crop; Dark HUD and Light HUD are available now.

The first physical cast also tests true OBD speed without pretending GPS is OBD. With the native OBD overlay experiment enabled and HUD-side OBD connected, the physical MJPEG frame reserves a blank speed-number area, then reasserts the recovered `OBD_DRIVING_VELOCITY` custom item (`itemIndex=10`) after streaming begins. If the HUD draws a speed value there, it comes from the stock HUD's ECU/OBD path. Disabling Map Mode clears the probe and restores normal Freeride/Navigation/dashboard state.

The September 11 time/weather field regression is also corrected: a saved OFF setting no longer sends the v90.34.16 transient ON→OFF cold-start edge. v90.35 uses OFF-only reasserts.

See `docs/V90_35_MAP_MODE_CAST_OBD_SPEED_CUSTOM_WIDGETS.md` and `V90_35_BUILD_VERIFY.txt`.

---

# v90.34.17 — Navigation map-video layout preview UI

v90.34.17 builds directly on v90.34.16.1 and adds the new **Map Video Display (Preview)** card to the iOS 26 Navigation screen. It uses the recovered CarPlay MainVideo map crop as the center visual and composes the proposed HUD layout as **speed / speed limit on the left, map in the center, maneuver + distance + street + lane guidance + ETA on the right**.

The preview prefers current app telemetry when a live route/speed is available and falls back to clearly illustrative sample values while parked. Preview-only controls allow Left–Center–Right, Map Focus, and Minimal compositions, map scale/crop adjustment, soft edge fading, and block nudging. These controls are intentionally local UI state: this release does **not** change HUD BLE packets, Route Guidance ownership, speed-limit matching, lane policy, U2W polling, ambient lighting, OBD, time/weather synchronization, or firmware-maintenance behavior.

This is the visual/calibration step before wiring a validated CarPlay MainVideo transport into the physical HUD. The production navigation path remains exactly the v90.34.16.1 path.

See `docs/V90_34_17_NAVIGATION_MAP_VIDEO_PREVIEW_UI.md` and `V90_34_17_BUILD_VERIFY.txt`.

---

# v90.34.16.1 — CI-only UART escape expectation fix

v90.34.16.1 changes **no runtime Swift source and no physical HUD behavior** from v90.34.16. The GitHub Actions app build completed successfully; the workflow failed only in `V903416TimeWeatherColdOffSpeedGaugeProbeTests.testRecoveredSpeedGaugePacketsEncodeAsKivicSDKDefines`.

The stale XCTest expected `DisplaySpeedCommandPacket (2/9/3)` as `02 7D 7F 09 03 01 03`. That expectation was invalid because `0x03` is the HUD UART ETX delimiter. `HudProtocol.frame` correctly byte-stuffs every in-frame `0x03` as `7D 7E`, so the actual and correct wire frame is `02 7D 7F 09 7D 7E 01 03`. The test now validates both that escaped wire representation and the unescaped logical body `[02,09,03,01]`.

Time/weather cold-OFF synchronization, D0–D3 speed-gauge probes, navigation, CarPlay/U2W, ambient lighting, OBD, lane guidance, and firmware maintenance are runtime-identical to v90.34.16.

See `docs/V90_34_16_1_CI_ESCAPE_TEST_FIX.md` and `V90_34_16_1_BUILD_VERIFY.txt`.

---

# v90.34.16 — cold-boot time/weather OFF synchronization + expanded native speed-gauge probe

v90.34.16 builds directly on v90.34.15 and keeps the production navigation, CarPlay/U2W, speed-limit matching, ambient-light, OBD, lane-guidance, Scale/Perspective, and firmware-maintenance behavior unchanged outside two targeted areas.

### Time/weather OFF cold-session synchronization

Two independent physical-HUD commutes showed the same state mismatch: the saved **Show weather/current time** setting was OFF and multiple OFF packets were transmitted after dashboard reconstruction, yet the panel stayed visible until the user manually toggled ON and then OFF. Repeating another plain OFF packet therefore is not sufficient on this HUD 1.1.27 cold-start path.

When the persisted setting is OFF, v90.34.16 now waits until the normal three-phase HUD rehydration and the existing 300 ms post-dashboard OFF reassert have completed, then performs one bounded synchronization edge: transient `timeWeather(true)`, wait 350 ms, then authoritative `timeWeather(false)`. The UserDefaults setting remains OFF the entire time. If the user changes the setting to ON before or during the sequence, the pending OFF synchronization aborts. Disconnects and a new HUD rehydration cancel any stale synchronization task.

### Expanded red-arc / speed-gauge probe

The v90.34.15 A/B/C controls remain. v90.34.16 adds diagnostic access to two recovered Kivic SDK packets that production code still does not assume are required:

- `DisplaySpeedCommandPacket` = `2 / 9 / 3`, boolean speed-information visibility;
- `DisplaySpeedGaugeCommandPacket` = `2 / 9 / 12`, boolean gauge visibility/state.

New temporary probes:

- **D0 — Gauge ON + zero threshold:** turns speed information/gauge on, resets the speed-limit packet to zero/style 0, and sends warning threshold 0. This directly tests the user's observation that the original HUD keeps a small red segment parked near zero when no posted limit exists.
- **D1 — Gauge ON + full stock speed chain:** enables the recovered gauge state, sends the stock Automatic/TRAVEL reset + `DisplaySpeedWarning(testLimit)`, then sends the later `setSpeedTolerance` packet (`limit=test`, tolerance 0, style 0) present in the original Android `applyHUDSettings()` sequence.
- **D2 — Gauge OFF→ON edge + stock chain:** forces a 350 ms false→true edge on `DisplaySpeedGauge`, then runs D1. This checks for a stale internal boolean/view relationship analogous to the time/weather issue.
- **D3 — Exact stock Freeride + gauge edge (parked):** temporarily applies the physically observed original Freeride dashboard `Speedo | Simple | Weather`, forces Navigation OFF, then runs the D2 sequence. This changes the dashboard and should be used parked.

**Restore current HUD** reapplies the user's Freeride/Navigation profiles, active dashboard mode, time/weather setting, turns the temporary experimental gauge boolean back OFF, and restores the current live speed-limit state. The probes do not change the selected speed-limit source, matcher cache, warning eligibility, or saved settings.

See `docs/V90_34_16_TIME_WEATHER_COLD_OFF_SPEED_GAUGE_PROBE.md` and `V90_34_16_BUILD_VERIFY.txt`.

---

# v90.34.15 — temporary stock speed-marker probe + time/weather boot persistence

v90.34.15 keeps the v90.34.14 production speed-limit logic unchanged and adds a temporary Vehicle-screen A/B probe for the small native speed-limit marker. Probe A sends the exact decompiled HUDWAY Drive 1.4.6 Automatic-mode sequence (`HudSpeedLimitAndTolerance(limit=0,tolerance=0,style=0)` followed by `DisplaySpeedWarning(testLimit)`). Probe B then restores the normal square sign after 350 ms; Probe C sends the current production sequence; a Restore button returns to the live matcher state. The diagnostic does not mutate source selection, cached limit, confidence, or saved settings.

The September 9 log also exposed the fresh-boot time/weather regression: the saved setting was OFF and OFF packets were sent, but they preceded subsequent Freeride/Navigation dashboard-profile reconstruction. v90.34.15 now sends the persisted time/weather state after dashboard reconstruction and performs one debounced 300 ms post-profile reassert whenever a Freeride or Navigation profile is applied. Enabled remains enabled; disabled remains disabled.

See `docs/V90_34_15_SPEED_MARKER_PROBE_TIME_WEATHER_BOOT.md`.

---

# v90.34.14 — native speed-limit marker + post-color ambient brightness restore

v90.34.14 builds on v90.34.13 without changing the validated Apple Maps arrival fix, CarPlay lane guidance, ETA, speed-limit matching, Scale/Perspective, or the reorganized UI. It adds two focused field-behavior refinements.

### Original HUDWAY native speed-limit marker

The speed engine continues to use the decompiled HUDWAY Drive 1.4.6 `DisplaySpeedWarningCommandPacket` (`2 / 9 / 9`) with the threshold equal to the confirmed posted speed limit. No custom arc is rendered by the iPhone. The HUD firmware remains responsible for drawing the small red threshold segment on its native speed gauge. v90.34.14 now reasserts that stock threshold after the HUD swaps between Freeride and Navigation renderers, and after a manual Freeride/Navigation widget-profile apply. This is intended to preserve the original red marker on the center `Simple` Freeride gauge and make the same global threshold available to the left-side `Speedo` widget in Navigation. Navigation-side rendering remains a physical-HUD behavior to verify; no firmware graphic is fabricated.

Lower-confidence/display-only limits retain the existing safety boundary: they may remain visible for continuity, but `DisplaySpeedWarning` is cleared so neither the native overspeed threshold nor its red marker is armed from an inferred value. Vehicle now shows a read-only **Native speed marker** status row reporting whether the stock threshold is armed.

### Ambient RGB brightness restore

The physical BLEDIM modules have been observed to jump to maximum brightness whenever an RGB/color command is written, matching behavior in the original BLEDIM app. v90.34.14 treats a manual color change (including device presets and group presets) as that hardware event and automatically returns the light to its semantic steady target.

- BLEDIM2: after RGB is accepted, the runtime is treated as physically 100% and smoothly returned to the resolved target over 1.0 second.
- Door: when vehicle day/night automation is enabled, the resolved target is the current confirmed Day or Night brightness selected by the Center/headlight state.
- Other lights: the resolved target is that light's saved preferred brightness.
- Groups: each member uses its own resolved target; a group color change does not force one common group brightness afterward.
- Lotus/ELK-BLEDOM: because the recovered protocol exposes independent RGB and brightness writes but we have not observed the same forced-100% behavior, the resolved target is simply reasserted once after RGB instead of fabricating a 100% ramp.
- Active Breath owns brightness: a manual RGB change does not cancel an active Breath; the existing animation's next frame and terminal target remain authoritative.
- Active ambient overspeed overlay owns color: a manual color selection is saved but the hardware RGB write is deferred until the normal overspeed restore, preventing the warning from being overwritten mid-pulse.

See `docs/V90_34_14_NATIVE_SPEED_MARKER_AMBIENT_COLOR_RESTORE.md` and `V90_34_14_BUILD_VERIFY.txt`.

---

# v90.34.13 — Apple Maps arrival zero-distance preservation

v90.34.13 is a narrow Route Guidance correctness fix on top of v90.34.12.1. A September 7 Apple Maps field capture showed the U2W v8.8 exporter correctly reporting `distanceToManeuverMeters=0` and `distanceToManeuverText="0"` at the destination while Apple Maps kept a stale destination-placeholder maneuver-table entry at `1931 m / 1.2 mi`. The previous iOS resolver treated every numeric zero as missing and fell back to that stale table entry, so the physical HUD was explicitly sent 1931 m and displayed 1.2 mi even though the app's live U2W fields were already zero.

The resolver now distinguishes an explicit live zero from an absent/ambiguous zero. A nonempty CarPlay display-distance field makes the live numeric distance authoritative even when it is zero, and Route Guidance `routeState=2` with both remaining distance and remaining time at zero also forces a zero-meter HUD maneuver. The historical maneuver-table fallback remains intact when the live numeric field is zero *and* the live display-distance field is empty, preserving compatibility with older/transitional captures.

Apple Maps can also replace its real final `Arrive at <destination>` maneuver with a blank destination placeholder. For that specific blank destination shape, the HUD street/text line now prefers the route's `destination` value instead of incorrectly falling back to `currentRoad`. Google Maps/Waze source priority, U2W v8.8 lane guidance, lane presentation policy, ETA, speed-limit matching, ambient lighting, Scale/Perspective, and the v90.34.12 UI reorganization are otherwise unchanged.

See `docs/V90_34_13_APPLE_ARRIVAL_ZERO_DISTANCE.md` and `V90_34_13_BUILD_VERIFY.txt`.

---

# v90.34.12 — UI reorganization + optional current-turn text

v90.34.12 builds on the physically validated v90.34.11 Scale/Perspective controls and cleans up the normal driving UI. The parked **Recorded CarPlay lane replay**, disproven **Lane placement** probe, and **Persistent stock music renderer** controls are no longer exposed. Their historical backend/source remains available for regression archaeology, but normal navigation stays on the proven `Speedo | Navigation | ETA` layout. Any persisted right-side lane-probe selection is migrated back to stock center placement so ETA cannot remain replaced by an empty side widget.

The persistent top shortcut bar now contains the same three rectangular shortcuts (**Navigation / Music / Ambient**) followed by compact **My Trips** and **Settings** icons. My Trips opens the existing Trips & Logs sheet. The fifth bottom tab is now **Ambient**, replacing My Trips. All ambient-light controls, HUD Center/BLEDOM auto-brightness configuration, and finite ambient overspeed-warning controls are centralized there; Vehicle retains OBD and speed/speed-limit source configuration.

Navigation adds **Show Current Turn Text** immediately below **Show Current Street**. Turning it off blanks only the maneuver packet's first text slot (for example `Turn right`, `Turn left`, or `U-turn`) while retaining the maneuver type/direction graphics, upcoming street name, current-street preference, distance, ETA, and lane guidance. The wire encoder preserves a leading empty line so disabling that first label cannot promote the upcoming street name into the turn-text slot.

Dashboard color swatches now use user-facing names that match the actual visible colors (the first three are Blue / Red / Green) while retaining the original HUDWAY enum identity and exact raw firmware color values. Explanatory prose across the primary cards now uses a reusable **Details** disclosure with a chevron; controls and live status remain visible when the prose is collapsed.

See `docs/V90_34_12_UI_REORGANIZATION_TURN_TEXT.md` and `V90_34_12_BUILD_VERIFY.txt`.

---

# v90.34.11 — Original HUDWAY display calibration + Settings UI

v90.34.11 adds the original HUDWAY Drive 1.4.6 **Scale** and **Perspective** controls using the stock BLE packets only. Scale maps the original 0–100 seeker to `LayoutSizeCommandPacket` values `0.00–0.20`; Perspective maps 0–100 to `KeyStoneCommandPacket` values `0.00–0.10`. Both use one big-endian Float32, persist locally, apply live while connected, and are reasserted after HUD reconnect/reboot. Slider sends are lightly debounced so dragging does not flood the serialized HUD BLE queue.

The app UI is also reorganized: a persistent **gear icon at the top right** opens Settings, and the existing **HUD Firmware Maintenance** / boot-animation card has moved out of Navigation into Settings beside the new HUD Display card. The maintenance implementation and its `/data/local/bootanimation` safety boundary are unchanged.

Per-widget scale/perspective was explicitly audited. The recovered calibration packets contain only a single Float32 and no left/center/right widget identifier; the dashboard packet only selects widget names. This build therefore does not invent an unverified per-widget command. Per-widget transforms remain a read-only firmware-research target.

See `docs/V90_34_11_DISPLAY_CALIBRATION_SETTINGS.md` and `V90_34_11_BUILD_VERIFY.txt`.

---

# v90.34.10.2 — Right-side lane probe candidate reconfiguration fix

v90.34.10.2 is a focused diagnostic follow-up to v90.34.10.1. Physical parked replay proved that the `Right probe: Navigation` candidate replaces ETA but renders no lane guidance on the right; the stock lane view remains in the center/bottom Navigation renderer. The field log also exposed a probe-state bug: changing the selector from `Right probe: Navigation` to `Right probe: NaviMini` while lane guidance was already active changed the setting but did not transmit a new dashboard packet, so NaviMini was never physically tested.

This build tracks the active right-side candidate and immediately reconfigures the dashboard when the selected probe changes. The Recorded CarPlay lane replay UI remains available for parked/home testing. The stock center renderer remains present during the probe, and no firmware/APK/system write is performed.

The gray `#252525` lane-container background remains a stock `HudLauncher` rendering constraint. This build does not patch the signed system launcher; the next rendering decision depends on whether the correctly-applied `NaviMini` side candidate can render lane information.

See `docs/V90_34_10_2_LANE_PROBE_RECONFIGURE.md` and `V90_34_10_2_BUILD_VERIFY.txt`.


## v90.34.12.1 — CI source-inspection alignment

GitHub Actions run `92497332769` confirmed that the v90.34.12 application target compiled successfully, but three older XCTest source-inspection tests still searched `VehicleView.swift` for ambient overspeed controls. v90.34.12 intentionally moved those controls to `AmbientLightingView.swift` as part of the requested Ambient-tab reorganization. v90.34.12.1 updates only those stale test source paths; runtime Swift sources and physical-HUD behavior are unchanged.

## v90.34.5.1 — CI replay-regression alignment

v90.34.5.1 is a **test-only correction** on top of v90.34.5. The supplied GitHub Actions run confirmed that the iOS 26 simulator app target built successfully and 209 of 210 XCTest cases passed. The sole failure was the older `V90344RecordedCarPlayLaneReplayTests.testReplayRemainsBLEOnlyDiagnostic`, which still required the pre-v90.34.5 direct replay call `HudCommands.laneGuidance(step.nativeLanes)`. v90.34.5 intentionally removed that direct send so recorded Apple/Google replay passes through `setLaneGuidanceForCurrentManeuver(...)`, the same configurable Off/Near turn/Persistent lane coordinator used by the new Navigation presentation settings.

**No runtime Swift source is changed in v90.34.5.1.** Configurable lane guidance, current-street suppression, HUD Wi-Fi exposure, recorded replay, mini Music diagnostics, CarPlay, speed limits, OBD, ambient lighting, and the zero-firmware-write boundary are identical to v90.34.5.

See `V90_34_5_1_BUILD_VERIFY.txt`.

---

## v90.34.5 — configurable native lane guidance + HUD Wi-Fi exposure

v90.34.5 keeps the v90.34.4 recorded Apple/Google `0x5204` replay and adds persisted Navigation presentation controls: Show Current Street, Lane Guidance Off/Near turn/Persistent, and a 0.1–1.0 mi near-turn threshold (0.5 mi default). Eligible lane packets are reasserted every 1.5 seconds to counter the stock HUD renderer's auto-hide behavior.

The iOS 26 Navigation screen also gains **Expose HUD Wi-Fi**, using only the stock Kivic-mode/hotspot BLE packets so a laptop can join the HUDWAY network at `192.168.43.1` while this custom app remains open and continues sending navigation commands. This does not start the firmware writer and performs no HUD filesystem write.

U2W v8.6 still exports only the lane-guidance-present flag rather than the decoded live lane array, so the recorded real-world fixtures remain the validation source for this build. See `docs/V90_34_5_CONFIGURABLE_LANES_HUD_WIFI.md`.

---
# HUD Controller v90.34.4.1 — CI regression alignment

v90.34.4.1 is a **CI-only correction** on top of v90.34.4. The supplied GitHub Actions run confirmed that the simulator app built successfully and all four new `V90344RecordedCarPlayLaneReplayTests` passed. The only failure was the older `V70ImperialUnitsAndUS1Tests.testNavigationReassertsImperialUnitsBeforeManeuver`, whose source-inspection assertion still searched for the pre-v90.34.4 literal `HudCommands.maneuver(current)`. v90.34.4 intentionally generalized that native send path to `HudCommands.maneuver(instruction)` so recorded CarPlay fixtures and live/manual navigation share the same sender. The runtime ordering remains unchanged: `HudCommands.imperialUnits()` is enqueued before the maneuver packet.

**No runtime Swift source is changed in v90.34.4.1.** Lane replay, mini Music, CarPlay, navigation, speed limits, OBD, ambient lighting, BLE protocol behavior, and the zero-firmware-write boundary are identical to v90.34.4.

See `V90_34_4_1_BUILD_VERIFY.txt`.

---

# HUD Controller v90.34.4 — Recorded CarPlay lane replay

v90.34.4 is a **zero-firmware-write parked diagnostic** on top of v90.34.3. The Navigation page can replay real Apple Maps and Google Maps `0x5204 LaneGuidanceInformation` events recovered from earlier physical U2W captures. Each step shows the original signed CarPlay lane angles, normalizes them to the five stock HudLauncher lane shapes, sends the captured maneuver context, and then sends the native `HudLanesManueverCommandPacket`. Previous / Next / 4-second Auto Replay controls let the physical renderer be validated at home before live lane integration is enabled. The v90.34.3 manual lane presets and mini-Music experiment remain available. No ADB, HUD filesystem, updater, APK, boot-animation, or live-adapter changes are made by this release.

See `docs/V90_34_4_RECORDED_CARPLAY_LANE_REPLAY.md` and `V90_34_4_BUILD_VERIFY.txt`.

---

# HUD Controller v90.34.3 — firmware-native lanes + mini Music diagnostics

v90.34.3 is a **no-firmware-write** diagnostic release on top of v90.34.2. Reverse engineering of the stock HUDWAY Drive `HudLauncher.apk` confirmed the exact `HudLanesManueverCommandPacket` encoding (`command=2, p1=113, p2=0`; signed lane values where positive=active and negative=inactive) and the stock mini-Music path (`MusicNotificationPacket` + `HudHUDWidgetsMiniState`). The iOS app now exposes controlled physical-HUD tests for both features without ADB, APK changes, remounting, updater commands, or firmware flashing.

Lane testing is deliberately manual first: four-lane presets can be sent from the Navigation diagnostics screen after entering Navigation mode. CarPlay lane metadata is **not** auto-injected yet. The Media screen can enter the stock firmware's mini state, send the current CarPlay Now Playing title/artist through the existing Music notification packet, and restore the normal UI. Automatic persistence/left-right placement is deferred until the physical renderer behavior is observed.

See `docs/V90_34_3_FIRMWARE_NATIVE_LANES_MINI_MUSIC.md`.

# HUD Controller v90.34.2 — iOS CI regression-test alignment

v90.34.2 is a CI-only correction on top of v90.34.1. Runtime navigation, CarPlay, speed-limit, HUD, OBD, and ambient-light behavior are unchanged. Two older Swift source-inspection tests still expected the pre-v90.34.1 behavior where every pending same-limit handoff disabled the native warning threshold. v90.34.1 intentionally changed that invariant: a trusted explicit same-speed handoff preserves the established threshold, while inferred/display-only continuity still disables warning trust. The Swift tests now assert that intended behavior, matching the already-updated Python regression tests.

Validation: 214 Python/static tests passed. The supplied GitHub Actions log showed the simulator app build itself succeeded; only the two stale XCTest assertions failed.

---

# HUD Controller v90.34.1 — Route Guidance cursor compatibility + persistent road speed continuity

v90.34.1 is a focused field-fix release on top of v90.34 and continues using **U2W CarPlay Data Exporter v8.6**. No adapter reflash is required for this app-side compatibility build.

The Route Guidance client now handles the v8.6 exporter's single-element `0x000D` quirk: if `currentManeuverIndex` is absent but the legacy `nextManeuverIndex` contains a valid maneuver table entry, that value is treated as the sole current maneuver. When both legacy fields are present, the first/current field still wins, preserving the v90.32 protection against selecting Apple Maps' secondary/future maneuver. A future corrected exporter may also provide `currentManeuverIndices[]`, which v90.34.1 prefers directly. Endpoint-response liveness remains unchanged, so stoplights do not return the HUD to Freeride.

The Improved + Philly speed matcher now keeps a confirmed displayed limit across strongly matched **untagged pieces of the same physical road/ref corridor**, including name↔ref transitions such as `Roosevelt Expressway / US 1` → unnamed `US 1 motorway_link`. This is display-only inheritance: overspeed warning trust is disabled while the value is inherited, and a new explicit conflicting speed (for example 50→40) still takes over through normal confirmation. Same-number explicit handoffs no longer unnecessarily toggle the native warning threshold off and back on.

CarPlay Now Playing, album artwork, ambient lighting, Google > Apple > Waze source priority, reroute stabilization, and the no-OCR locked-phone navigation architecture are otherwise unchanged from v90.34.

See `docs/V90_34_1_NAVIGATION_SPEED_CONTINUITY.md` and `V90_34_1_BUILD_VERIFY.txt`.

---

## v90.34 — CarPlay data integration

v90.34 pairs with **U2W CarPlay Data Exporter v8.6**. It keeps the proven adapter-only Route Guidance architecture, changes navigation liveness to successful endpoint reachability rather than Route Guidance sequence progression, adds a conservative Route Guidance connected-corridor OSM speed-limit inference for untagged road segments, and replaces the active Spotify SDK/token path with passive CarPlay Now Playing metadata + artwork from the U2W.

Current iOS/TestFlight workflows **do not require `SPOTIFY_CLIENT_ID`**. Legacy Spotify source files remain in the repository only for historical regression archaeology and are explicitly excluded from the app target. The current Music/Media runtime does not authorize Spotify, store a Spotify token, invoke the Spotify callback, or automatically launch Spotify.

See `docs/V90_34_CARPLAY_DATA_INTEGRATION.md` and `V90_34_BUILD_VERIFY.txt`.

---

> Historical release notes below describe older builds and may mention Spotify-era setup that is no longer required by v90.34.1.

# v88 TestFlight — restore existing GitHub secrets

The previous replacement workflow accidentally referenced a new secret naming
scheme (`P12_BASE64`, `PROFILE_BASE64`, etc.). The repository already had a
working TestFlight secret set, so those values resolved to empty strings.

This patch restores the existing secret names:

- IOS_CERTIFICATE
- IOS_CERTIFICATE_PASSWORD
- IOS_MOBILE_PROVISION
- APPLE_DEVELOPMENT_TEAM
- APPLE_API_KEY_ID
- APPLE_API_ISSUER
- APPLE_API_PRIVATE_KEY_BASE64
- SPOTIFY_CLIENT_ID

No new secrets are required.

The bundle identifier is derived directly from the App Store provisioning
profile, so `HUD_BUNDLE_ID` no longer needs to be a repository secret.

The workflow also validates all required existing secrets before installing
tools or trying to sign the app.

This fixes the latest failure:
`SecKeychainItemImport: Unable to decode the provided data`

It does not alter any v88 application source code.

Note: after signing/archive is restored, App Store Connect may still return
90534 if Apple's server continues rejecting the Xcode 27 beta 4 toolchain.
That is a separate external toolchain issue.



## v90.33 — Apple pre-road hold + geometry-gated Route Guidance speed assist + night-safe overspeed warning

v90.33 is a HUD-app-only update and continues using U2W v8.5 unchanged. The September 4 Apple Maps field capture showed a valid `routeState=6` pre-road/start-route phase with Route Guidance sequence gaps approaching 15 seconds before the vehicle joined the first routed road. v90.33 keeps the normal 4.5-second active-route freshness policy, but allows a genuine state-6 sequence to remain valid for up to 20 seconds. This prevents the physical HUD from bouncing Navigation → Freeride → Navigation while leaving a driveway/parking area. A truly dead/stuck state-6 sequence still expires after 20 seconds, and ordinary state 0 still exits Navigation immediately.

The Improved + Philly speed matcher now gates CarPlay's current-road semantic bonus by live GPS geometry. At driving speed, the full bonus requires a candidate within 40 m and within 45° of the vehicle course; a reduced bonus is allowed only through 50 m/70°. More contradictory geometry receives no Route Guidance bonus. Low-speed matching is distance-gated because course is noisy. Logs now include the raw `rgdCurrent=` road on OSM/GIS matcher lines, and `Martin Luther King Dr` is canonicalized against OSM's `Martin Luther King Junior Drive`. State 6 joins states 3/5 as a weakened route-transition context for speed matching. Posted speed values still come only from OSM/Philadelphia GIS.

Ambient overspeed warnings now have separate Day and Night brightness controls. Existing daytime brightness is migrated from the prior warning setting; Night defaults to 20%. Day/night selection uses the same confirmed Center/headlight state already used by Door brightness. After the finite warning pulses, RGB and brightness return to the preferred steady state through a one-second eased transition instead of snapping directly from warning red to the preferred color.

## v90.32.1 — CI XCTest alignment for restored original maneuver text

v90.32.1 is runtime-identical to v90.32. The iOS simulator build itself succeeded, but the workflow failed because the legacy v77 XCTest still required the OCR-era duplicate distance suffix (for example `Turn right • 0.2 mi`) in the maneuver text. v90.32 intentionally removed that suffix and restored the original HUDWAY presentation.

The stale XCTest is replaced with a packet-level regression test that verifies both intended invariants at once: the rendered maneuver text contains only the maneuver/street/current-road lines and does **not** contain the source distance or bullet, while the native HUD maneuver packet still carries the exact distance separately as the big-endian Int32 meter field. No application runtime code changed from v90.32.

See `docs/V90_32_1_CI_XCTEST_ALIGNMENT.md`.

## v90.32 — reroute-correct CarPlay maneuvers + route-assisted speed matching

v90.32 keeps the v90.31 adapter-only U2W v8.5 navigation pipeline and does not change Waze source priority. The physical HUD maneuver text returns to the original presentation (`Turn right`, `Turn left`, etc.) by removing the OCR-era duplicate distance suffix; the native maneuver distance field remains unchanged.

The Route Guidance client now interprets the exported maneuver cursor correctly: the **first valid current maneuver index** is the primary HUD instruction. `0xFFFF` is ignored, the client never falls back to maneuver 0, and the observed Google reroute sequence `5→0→3→1` keeps the last valid maneuver through a short same-source grace, and a new current maneuver must stabilize across two progressive Route Guidance snapshots before takeover. This addresses the field-observed N 33rd St reroute where v90.31 incorrectly displayed the second/future N 34th St maneuver instead of the current Mantua Ave turn.

The `Improved + Philly GIS` speed-limit matcher now accepts fresh CarPlay road context as a weighted road-selection hint. `currentRoad` strongly favors a matching but still geometrically plausible OSM/GIS candidate; the bonus is weakened during rerouting. The maneuver's after-road is used only as a post-turn tie-breaker once GPS geometry already proves the vehicle has rotated onto that road. **CarPlay never supplies the legal speed value**: OSM/Philadelphia GIS remain the sole posted-speed sources. Without an active/fresh CarPlay route, the existing GPS matcher behaves exactly as before.

See `docs/V90_32_REROUTE_AND_CARPLAY_SPEED_MATCHING.md`.

## v90.31 — adapter-only CarPlay Route Guidance + native ETA

v90.31 connects HUD Controller directly to the matched U2W v8.5 live Route Guidance exporter at `http://192.168.50.2/cgi-bin/u2wrgd-live.cgi`. Structured iAP2 `0x5201/0x5202/0x5204` data is now the **only automatic navigation source**. There is no OCR fallback: if the adapter endpoint is unreachable, reports no active route, or its Route Guidance sequence stops advancing for 4.5 seconds, HUD Controller sends Navigation OFF and the physical HUD returns to Freeride. A fresh adapter route automatically re-enters Navigation.

The app maintains fresh per-source leases and applies the requested priority **Google Maps > Apple Maps > Waze**. A higher-priority source wins only while its own stream is fresh, so an old Google Maps snapshot cannot suppress a currently updating Apple Maps or Waze route. Unknown sources are diagnostic-only and do not automatically take HUD ownership.

CarPlay `CPManeuverType` values map into the existing native HUD maneuver-arrow protocol. Current road, destination, next-maneuver distance, maneuver description/type, and maneuver table come from the adapter feed. ETA uses the original decompiled HUDWAY `HudEtaPacket` (`2/114/0`, signed 64-bit big-endian absolute arrival time in milliseconds). The client uses CarPlay's absolute ETA when available and otherwise computes `current time + TimeRemainingToDestination`.

The default Navigation dashboard is **`Speedo | Navigation | ETA`**. A one-time migration changes the legacy v90.30 `Time` default to `ETA` while preserving other explicit widget customizations. The existing speed/speed-limit pipeline remains independent and continues to own the left-side Speedo and legal speed-limit sign.

For locked-phone driving, ScreenCaptureKit is no longer a background dependency or automatic recovery path. The project retains its legacy OCR implementation only as diagnostic/source-history code; `.ocr` is rejected as a physical-HUD navigation owner. The live adapter poll starts with the HUD BLE session, while the existing continuous driving-location/background modes keep the app's vehicle session alive.

See `docs/V90_31_CARPLAY_ROUTE_GUIDANCE.md`.

## v90.30 — crank-stabilized HUD startup + fresh Dashboard headlight synchronization

v90.30 is a narrow ambient-light reliability update based on the stationary September 2 field test. The startup coordinator already achieved a strict 3/3 common T0 in v90.29, but Dashboard disconnected during the first Breath while the vehicle was still in its crank/accessory transition. A later headlight OFF→ON then admitted Center alone because CoreBluetooth still reported Dashboard as an already-active connection even though the physical Dashboard light was dark.

### Initial HUD-connected startup
- HUD transport remains the sole automatic-animation gate. OBD does not own ambient animation.
- After HUD transport becomes ready, startup now waits **5.0 seconds** before opening the strict Center + Door + Dashboard cohort. This lets the crank/accessory power disturbance finish before animation begins.
- The startup release remains all-or-nothing: Center + Door + Dashboard must all be GATT/control ready; one common T0 is used; no partial startup Breath is launched.
- Door's automatic day/night fade is suppressed while this startup stabilization/cohort owns the lights so it cannot inject independent writes before the shared T0.

### Later headlight OFF→ON
- Center/BLEDOM remains the authoritative headlight-power witness.
- When Center confirms OFF during an active HUD session, Dashboard's current BLE session is explicitly invalidated for the *next* headlight Breath. If CoreBluetooth still reports the Dashboard peripheral connected, that stale session is cancelled proactively.
- The next Center+Dashboard headlight cohort requires a **fresh Dashboard physical reconnect generation** before Dashboard can be prepared.
- A Dashboard disconnect while the strict cohort is still preparing no longer removes Dashboard from expected membership. The cohort stays Center+Dashboard and waits through the reconnect instead of silently shrinking to Center-only.
- The strict headlight readiness window is now **15 seconds**, bounded to cover the delayed Dashboard reconnect/GATT/boot-settle observed in the field log.

The BLEDIM production strategy and Breath waveform are unchanged (`Already-On Minimal`). Manual Preview is unchanged. Freeride/navigation runtime and the accepted v90.28/v90.29 speed-limit behavior are unchanged.

See `docs/V90_30_CRANK_AND_FRESH_DASHBOARD_SYNC.md` for the field failure and state-machine details.

## v90.29 — HUD-gated strict ambient sync + original Freeride mode restore

v90.29 steps back from the v90.28 Freeride watchdog and OBD animation-gate workaround after the corrected afternoon-drive chronology. The Freeride center RPM/bar disappeared **mid-drive** during a HUD/session rehydration, and relaunching our app repeated the same state. The original JADX-derived dashboard protocol remains `HudWidgetCommandPacket` (2/111/0): type 0 Freeride uses `center=Simple`, type 1 Navigation uses `center=Navigation`, with original SideWidget dash names on the sides. Those packets configure the two profiles; the active mode is separate. After each phase-2/phase-3 profile rehydration v90.29 now explicitly restores `Navigation OFF` when navigation is inactive (or `Navigation ON` when it is active). There is **no periodic Freeride watchdog** and no fabricated phone-side RPM/orange-bar rendering. The unused Minimize-widgets UI stays removed.

Ambient automatic Breath is now **HUD-transport-gated instead of OBD-gated**. Courtesy-light connections before HUD readiness remain steady. The first HUD transport connection arms one strict Center + Door + Dashboard startup cohort; only 3/3 ready members receive one common T0. Later headlight-ON events while HUD remains connected animate only the newly powered cohort, normally Center + Dashboard while an already-active Door is untouched. HUD disconnect re-arms the next startup opportunity. OBD remains diagnostic/corroborating vehicle state only and its v90.28 animation-gate-specific retry/grace changes are removed.

The accepted v90.28 speed fixes remain: same-road cache, MLK pending-same-25 no-blink continuity, warning-freshness separation, and the Philadelphia Street Centerline 650 m point+distance query with raw/speed/geometry/parsed diagnostics.

See `docs/V90_29_HUD_GATE_ORIGINAL_FREERIDE.md`.

## v90.28 — OBD gate reliability + original Freeride watchdog + MLK no-blink confirmation

v90.28 keeps the simplified v90.27 ambient state machine: courtesy-light connections never animate before OBD, the first positive OBD session owns one strict Center + Door + Dashboard startup Breath, and later headlight-ON events animate only newly powered members (normally Center + Dashboard while an already-active Door is untouched). The field logs showed the logic itself worked, but the HUD could delay its positive `OBDConnectionEventPacket` for minutes. OBD auto-retry therefore stays active at a bounded 3/4/5/8-second cadence instead of backing off to 30 seconds, and a previously positive OBD session survives a transient HUD transport/session reset for a 15-second reacquisition grace. An explicit OBD-disconnected event or grace expiry still publishes OFF immediately to the ambient gate.

The center Freeride/RPM presentation is now treated as firmware-managed display state that may silently drift even without a HUD reset event. v90.28 preserves the decompiled original Freeride packet semantics (`type=0`, `center=Simple`, user-selectable left/right SideWidget values) and reasserts that packet every 20 seconds while Navigation is inactive. The generic Dashboard `Freeride` preset also routes through the same original implementation rather than the older `center=Speedo` approximation. The unused **Minimize widgets** toggle is removed from the app UI; its persisted compatibility field and low-level protocol support remain harmlessly intact.

Speed matching retains v90.27's same-road cache and v90.26 turn/corridor logic. The remaining MLK blink was a one-sample race: a strong explicit same-road 25-mph successor could be at speed-source confirmation 1/2 while the four-second stale timer cleared the already-correct 25 sign. A pending source with the same mph as the displayed sign now counts as display-only continuity until 2/2 confirmation completes; native overspeed warning freshness remains disabled during that interim sample. Philadelphia Street Centerline requests now use a 650-m **point + distance** ArcGIS query (`esriGeometryPoint`, WGS84 input/output) instead of the WGS84 envelope shape that returned `rawFeatures=0` throughout the field logs. Raw/speed/geometry/parsed feature diagnostics remain enabled.

See `docs/V90_28_FIELD_RELIABILITY.md`.

## v90.27 — OBD-gated strict ambient sync + bounded same-road speed cache

v90.27 simplifies automatic ambient animation ownership around the user's requested state machine. **OBD connection is now the sole ignition gate for automatic Breath.** Courtesy-light connections before OBD remain steady and do not animate. When OBD connects, the app opens one strict startup cohort for Center + Door + Dashboard and waits up to 10 seconds for all three to become ready; only a full 3/3 cohort receives a common T0. Missing members cause the startup Breath to be skipped rather than releasing a partial or late catch-up animation. HUD transport remains available for engine diagnostics but no longer arms ambient startup animation.

After the one-time OBD startup opportunity, normal headlight-ON transitions remain automatic. Only newly powered lights participate. Center and Dashboard are explicitly paired as the headlight-fed cohort, so if either appears the other is enrolled and Center cannot start early while Dashboard is still settling. An already-active Door remains untouched. Headlight cohorts are also strict: all enrolled members must be ready before the shared T0 or that transition's Breath is skipped. Manual Preview remains unchanged.

Speed-limit handling retains v90.26's completed-turn takeover and corridor consensus, and adds a bounded **same-road display cache** to prevent MLK's 25 mph sign from blinking out during short OSM/cache holes. The cache is limited by road identity, 90 seconds, 1.2 km, and course compatibility when no OSM candidate exists; cached periods are display-only and immediately disable the warning threshold. A confirmed turn to another road invalidates the cache. Philadelphia Street Centerline logging now reports raw features, speed-bearing features, geometry-bearing features, and parsed segments so the persistent zero-result fallback can be diagnosed from one field log.

Media/navigation roadmap: structured **CarPlay adapter metadata is now preferred over further iOS 27 ScreenCaptureKit work** while the adapter test verifies Now Playing `0x5000/0x5001` and Route Guidance `0x5200`–`0x5204`. ScreenCaptureKit remains only an experimental fallback/reference path.

See `docs/V90_27_OBD_GATED_SYNC_SPEED_CACHE.md` and `docs/MEDIA_NAVIGATION_SOURCES.md`.

## v90.26 — admitted-member sync + post-crank recovery + fast new-road speed acquisition

v90.26 is the integrated field-fix build based on the 2026-09-01 drive log. Automatic headlight/courtesy synchronization now freezes physical membership after the normal 2.0 s discovery floor but **waits for an admitted live member to finish its known GATT/BLEDIM preparation** instead of releasing the common T0 underneath a 1.5 s BLEDIM boot settle. A configured light with only a stale persistent CoreBluetooth connect request no longer counts as physically present unless it is connected or has recent radio evidence. Manual Preview is unchanged.

The one-time initial engine-start exception now keeps a **15 s post-crank headlight/controller reacquisition window** (16 s bounded maximum) before deciding that the car truly started with the headlight-fed lights off. If Center + Door + Dashboard return and become controllable during that window, the existing engine-start full-cohort path waits for BLEDIM GATT quiet and releases all three on one common T0. Later headlight transitions remain new-joiners-only.

Improved speed matching now has a completed-turn takeover path that can drop sticky rolling-trace ownership when the prior road is clearly behind/perpendicular and a different named road is within 12 m and 20 degrees of the current travel direction. A hard road change immediately disables the inherited road's warning eligibility. For untagged current OSM pieces, a road-level speed may be displayed only when at least two nearby explicit OSM ways with the exact normalized road identity unanimously agree; this corridor inference is display-only until a local explicit source confirms it.

Philadelphia fallback was migrated from the old SpeedLimits service (which returned successful zero-feature queries throughout the field drive) to the maintained **Street Centerline** FeatureServer. The current layer exposes `POSTED_SPEED_LIMIT`, `SPEED_LIMIT`, and `FULL_STREET_NAME` on street polylines. The City matcher also has a tight 12 m / 20 degree current-geometry acquisition path after a turn so eight historical trace samples from the old road cannot delay a new-road limit for multiple blocks. The existing v90.25 same-road successor and pending-same-limit continuity protections remain intact.

See `docs/V90_26_AMBIENT_SPEED_ACQUISITION.md`.

## v90.25.1 — CI XCTest contract alignment

v90.25.1 is runtime-identical to v90.25. It updates the legacy `V9010AmbientPowerEpochReliabilityTests` source-contract assertion to the intentional v90.24+ synchronization implementation (`ownedByHeadlightBarrierNow` plus deferred Lotus visual preparation), fixing the iOS CI failure where 169/170 tests passed and the obsolete pre-v90.24 call-shape assertion failed.

## v90.25 — integrated ambient + speed continuity refinement

v90.25 keeps the complete v90.24 ambient synchronization fix and adds two field-driven **Improved + Philly GIS** display-continuity refinements. A close, aligned forward OSM successor with the same normalized road identity can now take over when the previous way's continuity bonus has become stale, fixing the residual MLK Drive dropout where the next MLK segment was physically much closer but narrowly missed the old score-delta gate. In addition, an explicit road candidate already at confirmation 1/2 with the **same mph as the displayed sign** temporarily suppresses the four-second stale clear, preventing a one-second blank such as the North 38th Street 25 → blank → 25 race.

Both paths are display-only continuity: they do not refresh overspeed-warning freshness and cannot use an untagged same-road segment to mask an explicit changed speed. v90.24's physical-new-joiner courtesy sync, readiness-only Lotus preparation, engine-start full three-light cohort, and Already-On Minimal behavior are unchanged.

See `docs/V90_25_SPEED_CONTINUITY_REFINEMENT.md`.


## v90.24 — physical auto-sync + engine-start full-cohort promotion

v90.24 fixes the field-observed case where manual Preview synchronized correctly but automatic courtesy/engine-start animation did not. Normal courtesy/headlight barriers now start from **physically present/connecting new joiners only** and keep a 2.0 s discovery floor for slightly delayed CoreBluetooth callbacks; an absent configured Door no longer holds a Center+Dashboard courtesy cohort open. Automatic Lotus/Center preparation is also **readiness-only**: no Power/RGB/baseline command is sent before the shared T0, eliminating the visible Center lead that could occur while a BLEDIM peer was still settling.

The initial confirmed engine OFF→ON edge is now the explicit startup exception to new-joiners-only behavior. Raw HUD engine ON reserves the crank window and suppresses a provisional partial cohort. After engine confirmation, the coordinator waits through a 4.0 s crank settle and requires BLEDIM GATT to remain ready for 1.5 s; once all enabled vehicle roles are controllable and the pipeline is idle, **Center + Door + Dashboard are deliberately promoted into one full startup cohort**, even if Dashboard had already been on from courtesy lighting. This promotion runs once per engine session and is re-armed by confirmed engine OFF. Later headlight transitions remain strictly new-joiners-only. A 9.0 s maximum wait prevents a missing controller from blocking forever.

Already-On Minimal BLEDIM behavior and the v90.22/v90.23 MLK same-road speed-limit continuity are unchanged.

See `docs/V90_24_AUTOMATIC_SYNC_ENGINE_START_PROMOTION.md`.


## v90.23 — newly joined lights only for synchronized Breath

v90.23 keeps the v90.22 **Already-On Minimal** BLEDIM production path and MLK/same-road speed-limit continuity, but narrows the headlight synchronization barrier to the intended physical behavior: **only lights newly joining the current transition are allowed to animate**. A controller that is already steady in its current BLE/power session is excluded and left untouched.

Example: if Door is already on and the headlights power Center + Dashboard, Door continues normally while only Center + Dashboard wait for one another and share the common Breath T0. Conversely, on a cold startup where Center, Door, and Dashboard are all still joining (including a Door whose startup Breath has begun but has not reached steady state yet), all three are treated as members of the same startup cohort and synchronize together.

The membership test considers boot-settle, Breath preparation, and an in-progress Breath to still be **joining**. Once a light has reached steady state in `animatedConnectionSession`, a later headlight edge cannot reset, prepare, or replay Breath on that light. The existing bounded barrier and late independent catch-up behavior remain unchanged for genuine new joiners. Flight-recorder entries now identify `syncMembership=newJoinersOnly` and log both the joining and untouched already-active roles.

See `docs/V90_23_NEW_JOINERS_ONLY_SYNC.md`.


## v90.22 — Already-On Minimal + headlight barrier sync + MLK speed continuity

v90.22 promotes the field-validated **Already-On Minimal** BLEDIM Breath to the only production/Preview strategy and removes the v90.21 strategy test lab from the UI. Door/Dashboard now avoid routine Power/RGB/baseline preparation writes and use a brightness-only final commit, preserving the smooth sequence without the observed start/end blink.

Synchronization is now driven by the **headlight ON transition**, not merely by whichever BLE controller finishes GATT first. The transition pre-registers all configured Center/Door/Dashboard participants, lets slower BLEDIM controllers finish their existing 1.5 s settle, then releases every ready member onto one common Breath timeline/T0. The barrier is bounded by the existing 3.0 s discovery window + 1.5 s preparation grace; a truly late controller receives a complete independent catch-up Breath instead of blocking the others. A one-time migration enables Sync on upgrade, after which the UI toggle remains user-controllable.

Improved + Philly GIS also gains **same-road speed-limit continuity** based on normalized road name/ref rather than raw OSM way ID. Adjacent pieces of Martin Luther King Junior Drive with the same explicit 25 mph limit can hand off immediately, and a geometrically continuous untagged MLK segment can preserve the displayed 25 mph sign without refreshing overspeed-warning freshness. Real road changes still follow the existing confirmation and four-second stale-clear path. Improved Trace logs now include `displayContinuity=0/1` and explicit same-road handoff decisions.

See `docs/V90_22_ALREADY_ON_MINIMAL_HEADLIGHT_BARRIER_MLK_CONTINUITY.md`.

## v90.21 — In-car BLEDIM animation strategy test lab

v90.21 keeps the v90.17.2 BLEDIM sequence as the production/default automatic behavior and adds a compact in-app test lab so Door/Dashboard start/end flash hypotheses can be compared without rebuilding. Six strategies are available: `17.2 Baseline`, `17.2 + Hold`, `No End Power`, `No End Commit`, `Already-On Minimal`, and the historical `18 No-Flash` experiment. The selected strategy applies to Preview immediately; automatic BLEDIM power-on remains v90.17.2 unless the user explicitly opts into applying the selected strategy automatically. A focused `Preview BLEDIM Only` action excludes Center/Lotus for easier visual comparison. Sync cohort, fast Center-driven day/night/HUD behavior, Improved OSM + Philadelphia GIS, provider backoff, and stale-sign handling remain unchanged from v90.20.

## v90.20 — v90.17.2 BLEDIM known-good rollback + v90.19 speed/provider improvements

v90.20 deliberately rolls Door/Dashboard BLEDIM behavior back to the last field-proven v90.17.2 implementation. The BLEDIM `0x80` boolean mapping is restored exactly (`ON -> 01`, `OFF -> 00`), Breath preparation is again `Power ON -> RGB -> baseline brightness`, and successful terminal commit is again `Power ON -> RGB -> final brightness`. The v90.18-v90.19 no-flash preload/semantic experiments are removed. This rollback intentionally accepts the small start/end visual flash seen in v90.17.2 in exchange for restoring reliable manual power, Preview, and automatic Breath behavior.

Later independent improvements remain: the true power-on sync cohort, fast Center/BLEDOM-driven HUD Auto Brightness and Door day/night target, 1-second Door automatic fade, three speed-limit modes, Improved OSM + Philadelphia GIS, corrected layer-specific Philadelphia fields, provider failure backoff, stale-sign clearing, warning safety, and the flight recorder. A one-time migration restores the known Door/Dashboard settings to configured ON so power states saved during the regressed builds do not suppress Preview.

## v90.19 — field-verified BLEDIM power semantics + Philadelphia GIS recovery

v90.19 fixes two field-proven v90.18.2 regressions. Both BK-BLE controllers demonstrated that BLEDIM command `0x80` uses payload `00` for physical ON and `01` for physical OFF; the earlier PacketLogger recovery had the correct raw frames but the UI-state labels were reversed. The corrected mapping is used everywhere (manual power, fresh-power Breath preparation, steady restore, and one-shot recovery) while RGB/brightness framing, per-controller sequence bytes, 20 Hz/raw-255 Breath, Center/Lotus behavior, fast Center-driven day/night logic, and brightness-only successful BLEDIM terminal commits remain unchanged. A one-time migration re-enables the known Door/Dashboard roles because the v90.18.2 field test intentionally saved them as OFF to work around the inverted mapping.

The Improved + Philly GIS provider now uses layer-specific ArcGIS fields, a WGS84 ~500 m envelope query, independent posted/residential layer failure handling, and a 12-second failure retry backoff. The old implementation incorrectly requested `SpeedLimits_MPH` from Residential Streets, a field that exists only on Street Speed Limits; every City request therefore failed and retried nearly every GPS update. Improved OSM gets the same failure backoff. Philadelphia GIS matching remains able to supply a speed independently of OSM, so local streets can still resolve while Overpass is temporarily unavailable.

## v90.18.2 — iOS CI XCTest architecture-alignment fix

v90.18.2 keeps the v90.18.1 runtime behavior unchanged and fixes two stale XCTest source-text assertions that depended on the capitalization of a comment. The tests now verify the actual architecture instead: power-on animation admission remains independent of engine/courtesy/headlight state, Sync cohort registration precedes BLEDIM boot settle, and every CoreBluetooth reconnect clears the per-connection animation-consumed flag. The flight-recorder version label is updated to v90.18.2 for field-log identification.

## v90.18.1 — Xcode 26.6 Philadelphia GIS actor-isolation fix

v90.18.1 is a compiler-only hardening revision of v90.18. It moves the pure Philadelphia GIS numeric parsing helpers out of a nested `compactMap` helper and marks them `nonisolated static`, avoiding Swift 6 main-actor inference inside a synchronous collection transform. Ambient behavior, BLEDIM transport, sync behavior, speed-source algorithms, and GIS matching policy are unchanged.

## v90.18 — no-flash BLEDIM + fast Center day/night + true sync + Philly GIS

v90.18 keeps the v90.17 per-light fresh-power architecture that eliminated the recurrent
stuck-OFF behavior, then focuses on the remaining field-observed issues:

- BLEDIM Door/Dashboard preload RGB + baseline around Power ON and use a brightness-only
  terminal commit on successful Breath completion, avoiding routine start/end Power ON
  flashes while retaining the one-shot Power/RGB/brightness fail-safe for actual failures.
- Center/BLEDOM presence again owns the fast day/night edge used by both HUD Auto
  Brightness and Door target brightness. Dashboard+Center consensus is diagnostic only.
- Automatic Door day/night transition is a dedicated 1.0 s fade; manual/group fade
  duration remains independently adjustable.
- Optional Sync ON now forms a 3.0 s power-on cohort before protocol preparation and then
  gives expected devices a bounded 1.5 s preparation grace before one common Breath T0.
  Late devices still receive a complete independent Breath.
- Speed-limit sources are reduced to **Current**, **OSM Trace**, and **Improved + Philly
  GIS**. Existing OSM Trace remains the field-tested A/B baseline.
- Improved mode loads untagged drivable OSM roads so entering a neighborhood can break
  continuity with a prior arterial, clears a stale sign after 4 s without a fresh speed
  source, and fixes the unmatched-trace infinite-score sentinel bug.
- In Philadelphia, Improved mode also fuses the City's public Street Speed Limits and
  Residential Streets ArcGIS layers. A confident explicit OSM motorway match is protected
  from a nearby surface-street GIS override; outside Philadelphia or if City GIS is
  unavailable, Improved mode continues with improved OSM only.

See `docs/V90_18_NO_FLASH_FAST_CENTER_TRUE_SYNC_PHILLY_GIS.md`.

## v90.17 — simple power-on ambient lifecycle + optional sync + OSM Trace flight recorder

v90.17 deliberately removes engine/courtesy/startup state from ambient animation admission.
Every controller return is a fresh power-on event: GATT readiness (plus a 1.5 s BLEDIM
firmware settle) leads to Power ON → RGB → complete Breath → a semantic Power ON/RGB/final
brightness commit. A disconnect immediately re-arms that light for the next return.

Power-on synchronization is now optional and defaults OFF. With sync enabled, prepared
lights have a 2.5 s grouping window; a late controller always receives its own complete
Breath rather than joining mid-cycle. Dashboard + Center consensus is independent and only
controls Door day/night brightness plus HUD Auto Brightness.

The ambient flight recorder remains enabled, and OSM Trace diagnostics now log the exact
GPS trace, top candidate roads, nearest OSM geometry, scoring/margins, speed tags, decision,
and final resolved/held speed limit. See
`docs/V90_17_SIMPLE_POWER_ON_AND_OSM_TRACE_DIAGNOSTICS.md`.

### v90.17.1 — pre-drive audit hardening

A second adversarial source audit before field testing found and corrected several edge
cases without changing the v90.10-derived BLEDIM packet format or 20 Hz/raw-255 animation
transport:

- A failed terminal Breath commit is no longer logged/cleared as success. If the final
  semantic `Power ON → RGB → preferred brightness` sequence fails, the existing one-shot
  steady-state fail-safe is armed.
- Shared/group brightness fades now carry an ownership token. Cancelling one member cleans
  up every member of that same shared task, preventing stale `fade` ownership from
  suppressing later restores.
- OSM Trace now distinguishes a **fresh road resolution** from merely holding the previous
  sign while no candidate is eligible or a road switch is still pending/rejected. Held
  signs remain visually available for continuity but do not refresh the 12-second
  overspeed-warning freshness clock. `OSM TRACE OUTPUT` logs `fresh=0/1`.
- Engine diagnostic OFF no longer uses Door power as a veto, because the vehicle can retain
  Door accessory power after engine shutdown. Engine diagnostics remain completely
  independent of ambient animation admission.
- Vehicle settings text now describes the actual Dashboard+Center consensus ownership of
  HUD Auto Brightness.
- Packaging excludes `.pytest_cache`, `__pycache__`, and `.pyc` artifacts.

### v90.17.2 — Xcode 26 XCTest alignment + Preview steady-target hardening

Xcode 26.6 CI confirmed the application target builds successfully. The CI failure was
limited to three stale XCTest assertions left over from the pre-v90.17 architecture.
v90.17.2 aligns those tests with the per-light model and also strengthens manual Preview:
it now seeds its Breath from the resolved steady target (Door day/night target or the
device preferred brightness) instead of a potentially transient `runtimeBrightness` left
by an interrupted animation. This does not change the automatic power-on Breath waveform,
BLEDIM packet format, 20 Hz pacing, optional synchronization behavior, or day/night
consensus.

## v89 — direct ambient-light control foundation

v89 expands the existing ELK-BLEDOM presence monitor into a single multi-device
CoreBluetooth subsystem. The existing BLEDOM → HUD Auto Brightness behavior is
preserved, but it is now independently switchable from direct ambient-light
control.

### Lotus Lantern / ELK-BLEDOM

The supplied Lotus Lantern 6.5.08 decompile exposes its BLE implementation. v89
implements that protocol directly:

- GATT service: `FFF0` (`0000FFF0-0000-1000-8000-00805F9B34FB`)
- write characteristic: `FFF3` (`0000FFF3-0000-1000-8000-00805F9B34FB`)
- power ON: `7E 04 04 01 00 01 FF 00 EF`
- power OFF: `7E 04 04 00 00 00 FF 00 EF`
- RGB: `7E 07 05 03 RR GG BB 10 EF`
- brightness: `7E 04 01 XX FF FF FF 00 EF` where `XX` is 0–100

The app restores the saved color, brightness and power state after connection.
It can also play a software-generated startup pulse: fade up/down once or twice,
then fade back to the saved target brightness. A 15-second disconnect threshold
prevents a momentary BLE dropout from replaying the startup animation.

### Pairing and groups

The Ambient Lighting page supports:

- discovery of named and unnamed BLE peripherals;
- persistent user names for lights;
- remembered CoreBluetooth peripheral identifiers;
- independent automatic reconnection;
- app-level groups containing any subset of paired lights;
- membership of one light in multiple groups;
- group power, color and brightness fan-out through per-device protocol adapters.

The two unnamed BLEDIM2-compatible lights can therefore be placed in their own
group without including the ELK-BLEDOM controller.

### BLEDIM2 protocol status

The supplied BLEDIM2 1.960 APK is protected with the Jiagu/360 packer. Its
visible DEX contains the protection loader and references such as `libjiagu.so`
and `libjgdtc.so`; the real BLE command builder is not present in JADX output.

v89 intentionally does **not** guess BLEDIM2 write packets. It already supports
BLEDIM2 discovery, pairing, automatic reconnection, grouping, and complete GATT
service/characteristic fingerprint logging. Once one BLEDIM2 Bluetooth HCI
capture is supplied, the final adapter can be added without changing the UI,
group model, or connection architecture.

## v89 temporary iOS 26 ambient-light TestFlight flavor

A parallel Xcode 26 build flavor is included for testing Ambient Lighting while
the Xcode 27 GitHub preview image is unavailable/incompatible. Run the GitHub
Actions workflow **Build and Upload iOS 26 Ambient TestFlight**. It compiles
with `ios/project-ios26-ambient.yml`, which excludes the iOS 27
ScreenCaptureKit implementation but keeps the v89 ambient-light subsystem and
the rest of the HUD controller. See `docs/V89_IOS26_AMBIENT_TEST.md`.

## v90 — vehicle-aware ambient lighting + BLEDIM2/CB01 test control

v90 builds on the iOS 26 ambient-test branch and adds the physical car-light
state machine documented in `docs/V90_VEHICLE_AMBIENT_AUTOMATION.md`.

Highlights:
- enables experimental BLEDIM2/CB01 control on the physically observed
  `FFF0/FFF1` GATT path;
- auto-migrates the known Door, Dashboard and Center Console controller roles;
- day startup pulses the Door light only;
- night startup pulses all powered role lights synchronously;
- later headlight activation fades in Dashboard + Center Console together;
- shutdown test fades active lights to runtime 0 without overwriting preferred
  brightness;
- preserves the Xcode 26 temporary CI/TestFlight path and the reserved monotonic
  TestFlight build-number range;
- leaves the stock-default Automatic speed-warning packet behavior unchanged;
  the missing physical orange threshold tick remains a separate visual-renderer
  audit item.

v90 final test packaging also keeps late GATT readiness eligible for the normal
headlight-join fade and avoids persisting UserDefaults on every intermediate fade
frame; only final runtime brightness states are committed.


## v90.1 — engine-switched HUD/OBD power state

The physical HUD and OBD2 adapter in this vehicle are both hardwired to an
engine-switched fuse. v90.1 therefore uses that power domain directly instead of
requiring a live RPM PID:

- HUD transport ready => engine power ON immediately;
- OBD connection through the HUD => corroborating engine power ON;
- HUD transport lost + OBD unavailable => engine OFF candidate;
- both signals must stay absent for the configurable confirmation delay (default
  2.0 s) before engine OFF is committed;
- any HUD/OBD recovery during that window cancels the candidate as a transient BLE
  dropout;
- confirmed engine OFF automatically runs the existing fade-to-runtime-0 shutdown
  path without changing preferred brightness.

The manual **Fade Out Now** control remains for stationary diagnostics. Vehicle
startup classification now requires engine power ON plus the door/headlight light
presence pattern, so an ambient-light reconnect by itself cannot create a false
new driving session.

## v90.2 — HUD thermal/reboot protection with independent OBD witness

- A HUD BLE disconnect by itself no longer counts as engine OFF.
- HUD-side OBD link state is cleared on HUD loss for UI correctness, but that event is no longer emitted as physical OBD power loss.
- The existing ambient CoreBluetooth scan watches the configured OBD name (`OBDII` by default) and can learn its iOS UUID when the HUD is deliberately switched off while the engine remains running.
- Once calibrated, direct OBD BLE advertisements veto shutdown during HUD-only overheat/reboot outages.
- Automatic shutdown is inhibited until the independent OBD witness is calibrated. If the OBD adapter is Bluetooth Classic and cannot be observed by iOS, the app refuses to infer engine OFF and keeps `Fade Out Now` as the safe manual path.

## v90.3 — automatic door day/night brightness

The door controller is powered for the entire engine session, so v90.3 gives it
two independent vehicle-automation brightness targets:

- **Door daytime brightness** (default 100%)
- **Door nighttime brightness** (default 45%)

Night/headlight state is redundant: either the Dashboard light **or** the Center
Console/BLEDOM light being logically powered is sufficient to select the night
target. Day returns only after both headlight-fed controllers are absent.

The door transitions use the existing Headlight join fade duration. At a
daytime startup the door pulse ends at the daytime target. At a nighttime
startup its synchronized pulse ends at the nighttime target while Dashboard and
Center Console end at their own preferred brightness. If headlights turn on
later while driving, Dashboard/Console fade in while Door fades to its night
target. If headlights later turn off and both headlight-fed lights disappear,
Door fades back to its daytime target.

These day/night values are separate from the door device's generic/manual
preferred brightness and only update runtime/last-applied brightness. Engine
shutdown still fades all powered lights to 0 without destroying any preferred
or day/night target.

All v90.2 HUD-outage protection and independent OBD witness logic is retained.

## v90.4 — courtesy-headlight-aware engine startup

Vehicle-entry behavior was corrected: Dashboard + Center Console can be powered by courtesy headlights before the engine starts in both daylight and darkness. v90.4 therefore ignores pre-engine headlight-fed presence for startup classification. Once engine-switched HUD/OBD power appears, the app waits the configurable post-engine settle window. If the headlight-fed pair turns off, the startup is Day and only Door pulses to its daytime target. If either remains powered, the startup is Night and the available role lights pulse together, with Door ending at its nighttime target.

## v90.5 — retire invalid BLEDIM packets + corrected arrival/courtesy shutdown

Field testing proved that both BLEDIM2-compatible controllers accept the BLE
connection and expose `FFF0/FFF1`, but ignore the v90 `7E FF ... EF` packet
family. Those guessed writes are removed. BLEDIM normal Power/Color/Brightness
and automated fades are intentionally disabled until the exact FFF1 application
payload is captured.

A new per-device **BLEDIM FFF1 Protocol Lab** records advertisement metadata,
reads standard Device Information/Battery values, logs FFF1 notifications, and
can replay an exact captured hex frame only to FFF1. It never writes the TI OAD
`F000FFC0/FFC1/FFC2` firmware-update service.

Shutdown behavior is also corrected for the physical wiring. Door is engine-fed
and loses power immediately at engine OFF, so the app records Door runtime 0
without trying to fade it. Dashboard + Center Console are headlight-fed and the
shutdown latch stays armed until the next engine start, allowing verified
headlight controllers to be faded/held at 0 during the post-lock 1–2 minute
courtesy-headlight interval. Until BLEDIM FFF1 is decoded, this suppression is
fully available for Lotus but not yet for the BLEDIM Dashboard light.


## v90.5.1 — iOS 26 TestFlight compile fix

The v90.5 TestFlight archive reached Swift compilation but failed in
`AmbientLightingView.swift` because the `bledimUndecoded` UI guard was declared
inside the LIGHT CONTROL section and then referenced again from the sibling
STARTUP ANIMATION section. v90.5.1 moves that guard to the common paired-device
scope. No BLE protocol, vehicle-state, or shutdown behavior changes from v90.5.
A source regression test now requires the guard to remain in the shared scope.

## v90.5.2 — iOS CI stale shutdown-test fix

The iOS 26 application build passed, but one older v90 source-inspection unit test
still expected the pre-v90.5 shutdown implementation. The test now matches the
corrected Door-power-loss/headlight-courtesy shutdown behavior. No runtime code
changed from v90.5.1.

## v90.7 — BLEDIM2 official iOS protocol recovered

An Apple Bluetooth diagnostic/sysdiagnose PacketLogger capture of the official BLEDIM2 iOS app resolved the previously unknown FFF1 command protocol. BLEDIM2 uses `55 AA` framed writes with an incrementing sequence byte, big-endian payload length, and an additive modulo-256 checksum. Captured commands are `0x80` power, `0x82` RGB, and `0x88` brightness. Normal BLEDIM controls and vehicle automation are re-enabled; the disproved v90 `7E FF ... EF` guesses remain retired. See `docs/V90_7_BLEDIM2_OFFICIAL_IOS_PROTOCOL.md`.


## v90.8 — simplified ambient state machine, smooth breath, presets, shortcuts

v90.8 supersedes the earlier startup/headlight-join/shutdown choreography. Field
observation established that all three ambient-light controllers can remain powered
after engine shutdown, so engine OFF no longer sends any automatic ambient-light
brightness or power command. The vehicle-state machine is intentionally limited to
one responsibility: while the engine-power session is ON, Dashboard or Center
Console headlight presence selects the Door's night target; absence of both selects
the Door's day target. A short internal post-engine settle still rejects the
pre-engine courtesy-headlight state.

Ambient animation/control is now independent of that vehicle state machine:

- one optional per-light **Animation on power-up** toggle (fresh BLE/power session or manual OFF -> ON);
- one global **Breath** animation only: current -> 0% -> 100% -> current;
- user-selectable 2x, 3x, 4x, or 5x repeats;
- user-selectable 1-15 second total breath duration;
- enabled lights discovered together are coalesced onto one shared animation clock,
  and late GATT-ready lights join the current breath phase;
- every manual device/group brightness change and every automatic Door day/night
  change uses a shared 1-15 second smooth transition instead of a target jump;
- animation/transition frames run on a 20 Hz scheduler and suppress duplicate rounded
  brightness writes.

Each individual light and each group now has five persistent color preset blocks.
Tap a block to apply it; long-press a block to replace that slot with the current
color-picker value. Device presets and group presets are independent.

The Ambient Lighting page no longer exposes the general Nearby BLE Devices list.
CoreBluetooth scanning, remembered UUID reconnect, OBD witness detection, and all
paired-light behavior remain active in the background.

A persistent three-button quick-action strip appears at the top of every main app
surface except My Trips/Logs:

- **Navigation** selects Navigation, arms HUD navigation, and presents the full-display
  capture picker in the normal iOS 27 build;
- **Music** selects Media and performs a one-tap Spotify recovery, authorizing only if
  needed or otherwise waking Spotify/resuming App Remote without clearing Keychain;
- **Ambient** selects Vehicle and deep-links directly to Ambient Lighting -> Paired
  Lights.

The BLEDIM2 protocol remains the official iOS-capture `55 AA` FFF1 implementation.
The 2026-08-24 PacketLogger capture was made with the **Dashboard** BLEDIM controller,
not Door; later field testing confirmed the same protocol works on both controllers.


## v90.8.1 — Breath duration clarification

- Breath always uses each light's actual runtime brightness at animation start; 50% was only an example.
- One repetition is `initial/current → 0% → 100% → initial/current`.
- If a manual or active Door day/night target changes while the breath is running, earlier repetitions still return to the original starting brightness and the final repetition returns smoothly to the latest target.
- `Breath duration / cycle` is 1–15 seconds **per repetition**. Therefore 3× at 9 seconds takes 27 seconds total.

## v90.8.2 — iOS CI breath regression fix

- Runtime behavior is unchanged from v90.8.1.
- Fixes a stale Swift source-regression assertion that still expected the pre-v90.8.1 fixed return leg (`100% -> initial`) on every breath cycle.
- CI now validates the intended v90.8.1 behavior: earlier cycles return to the captured initial brightness, while only the last return leg may end at a target changed during the running breath.
- CI also verifies that the configured breath duration is per cycle and total duration is `per-cycle duration × cycle count`.

## v90.9 — BLEDIM animation pacing + reliable Breath + editable presets

Field logs from v90.8.2 showed that the animation problem was transport/timing related,
not a different brightness opcode. The official BLEDIM2 iOS PacketLogger capture sends
continuous brightness-slider updates at roughly 100 ms intervals (~10 Hz), whereas
v90.8.2 drove both BLEDIM controllers at 20 Hz. During synchronized Breath this was
combined with one interleaved sequence counter for both BLEDIM peripherals, repeated
GATT rediscovery/read traffic, and synchronous per-frame logging on the MainActor.
The field log also showed real BLE timeout disconnects and an important re-entry bug:
a second Preview/power-up request could recapture a 1–5% in-progress animation frame
as the new return brightness, causing the Breath to finish nearly dark.

v90.9 therefore:

- keeps one shared wall-clock animation phase, but paces BLEDIM brightness writes at
  <=10 Hz and Lotus Lantern at <=20 Hz;
- uses a separate BLEDIM sequence counter for each physical controller;
- checks CoreBluetooth `canSendWriteWithoutResponse` and drops stale intermediate
  frames under backpressure instead of building a write queue;
- calculates progress from elapsed wall-clock time, so scheduler/BLE delays skip stale
  frames rather than extending a requested animation indefinitely;
- suppresses intermediate animation packet logging and rate-limits repetitive BLEDIM
  all-`FF` notification logs;
- stops rediscovering services on every watchdog pass once a control characteristic is
  already ready;
- ignores a repeated Preview/ON request for a light already participating in the active
  Breath, preserving its original start/return brightness;
- restores the saved steady-state target after a reconnect instead of an interrupted
  animation frame;
- keeps the common synchronized phase so Door, Dashboard, and Center remain visually
  aligned as closely as their different BLE transports allow.

The five device presets and five group presets are now visibly editable. Pick any color
with the normal picker, then tap the pencil under a preset slot to overwrite that slot.
Tap the color block itself later to apply it. Long-press replacement remains available
as a secondary interaction.

## v90.10 — physical headlight epochs + reliable ambient command delivery

Field logs from v90.9 showed that the remaining failures were primarily state-machine
and CoreBluetooth delivery problems rather than an incorrect BLEDIM2 command format.
Semantic writes such as Power ON, RGB restore, and final brightness could be skipped
when `writeWithoutResponse` backpressure was active, while the animation state machine
continued as if they had succeeded. The known vehicle lights were also being
cancelled/reconnected by the old six-second watchdog, and Dashboard/Center Breath
re-arming still depended on the older 15-second disconnect heuristic.

v90.10 changes the ambient runtime around the actual vehicle power behavior:

- Dashboard + Center Console use a **physical headlight-power epoch**. A new physical
  OFF -> ON event can start a fresh Breath immediately, even if the previous OFF interval
  was only a few seconds.
- A short dual-controller OFF debounce cancels an in-progress headlight Breath and lets
  a rapid ON/OFF/ON sequence start cleanly without stale animation ownership.
- Door day/night automation is brightness-only. A headlight state change cancels the
  old Door transition and smoothly retargets from the Door's current runtime brightness;
  it no longer resends Power/RGB as part of every day/night transition.
- Power, RGB, Breath baseline, restore brightness, and final brightness are serialized
  through retry-aware `writeWithoutResponse` helpers instead of being silently dropped
  under CoreBluetooth backpressure.
- The three known vehicle ambient controllers are exempt from the old six-second
  cancel/reconnect watchdog loop; pending connections are allowed to complete naturally
  when physical power becomes available.
- BLEDIM animation brightness uses the decoded protocol's native 0...255 resolution on
  the shared 20 Hz wall-clock phase. Logical 0% is a brightness command and is never
  converted into a BLEDIM Power OFF command.
- Breath uses a linear slider-like ramp while preserving the per-cycle duration model
  introduced in v90.8.1.
- Opening an individual or group control page initializes its color picker silently;
  simply visiting the page no longer emits an RGB command. Preset taps also issue only
  one RGB command.

The v90.9 source-regression tests were updated to validate these v90.10 invariants.

## v90.14 — v90.10 lighting baseline + two-light headlight consensus

v90.14 deliberately returns the ambient-light transport/choreography to the v90.10 baseline, which produced the best in-car behavior. BLEDIM2 keeps the v90.10 20 Hz/raw-255 animation path, per-peripheral sequence handling, reliable Power/RGB/final-brightness writes, and normal GATT discovery. The later v90.13 repeated steady-state recovery rounds, BLEDIM 10 Hz experiment, and Center-authoritative headlight state are not used.

Headlight power is now a stable two-controller consensus. Center + Dashboard both ON for 0.75 s confirms headlight ON; Center + Dashboard both OFF for 0.75 s confirms headlight OFF. A mixed state preserves the last confirmed state. A new headlight Breath is admitted only after both controllers are GATT-controllable, preventing one controller from joining halfway through. A same-epoch reconnect therefore restores the normal v90.10 device state instead of creating another physical headlight epoch.

HUD auto-brightness uses the same confirmed consensus edge, so a Center-only radio dropout cannot flip the HUD or Door day/night state while Dashboard still indicates headlight power.

The independent later features remain: Spotify automatic wake is allowed only in a HUD/OBD vehicle session; speed-limit selection includes Current, Enhanced OSM, and OSM Trace; the finite ambient overspeed warning supports a user-selected color (red default), 0–5 s pulse duration, 2–3 pulses, brightness/offset controls, and a 60 s recross cooldown. No HERE code, API key, or commercial map-service dependency remains.

## v90.14.1 — CI compatibility test alignment

- No runtime ambient-light behavior changes from v90.14.
- Replaces the legacy `V9012AmbientRecoveryOverspeedSpotifyGateTests.swift` file so overlay-style repository updates cannot retain v90.12/v90.13 assertions that contradict the v90.14 two-light consensus architecture.
- The compatibility XCTest now validates stable Center+Dashboard consensus, both-GATT-ready Breath admission, same-epoch single steady restore, the v90.10 BLEDIM transport baseline, and the retained overspeed/Spotify behavior.


## v90.15 — courtesy-safe startup + HUD/OBD engine consensus

v90.15 keeps the v90.10 ambient BLE transport and the v90.14 two-light headlight consensus, but separates pre-engine courtesy lighting from the actual driving startup sequence.

- Engine ON is a stable two-signal consensus: HUD transport + OBD2 connection must both be present for 0.75 s before a new vehicle session is created.
- Engine OFF is considered only when both HUD and OBD2 are absent. A mixed state preserves the last confirmed engine state.
- The independent direct-OBD BLE witness can veto a false engine-OFF decision during a HUD reboot, but it cannot create a new engine-ON session by itself.
- HUD transport loss now also publishes the through-HUD OBD connection as disconnected, allowing the two app-visible states to remain internally consistent. Direct OBD remains the physical-power fallback witness.
- Dashboard + Center courtesy power while the engine is unconfirmed may connect and restore normally, but cannot create a headlight epoch or consume the automatic startup Breath.
- Once HUD + OBD2 confirm engine ON, the existing courtesy settle classifies the real post-start lighting state.
- Day startup waits for Door control and runs one Door Breath.
- Night startup waits for Door + Dashboard + Center writable GATT control and then admits one synchronized three-light Breath.
- Startup classification no longer launches a separate Door day/night fade before the Breath; the Breath owns the Door baseline/return target, eliminating competing startup brightness timelines.
- After startup, v90.14's Center+Dashboard headlight consensus remains in charge: mixed state preserves the last confirmed state, both ON creates one headlight epoch, and both OFF ends it.
- A 5-second direct-OBD acquisition window plus the existing engine-OFF confirmation delay protects against short HUD-only reboots before declaring a new engine session.

All later independent overspeed, Spotify vehicle-gating, and OSM speed-limit features remain unchanged.

### v90.15.1 — narrow animation-abort brightness fail-safe

- Keeps the v90.10-derived ambient BLE transport, 20 Hz/raw-BLEDIM Breath, courtesy-safe startup, HUD+OBD engine consensus, and two-light headlight consensus unchanged.
- If an active Breath or smooth brightness transition is cancelled and no newer light operation takes ownership, a deferred one-shot fail-safe restores Power ON, the normal color, and the current steady preferred brightness through the existing `restoreDeviceState` path.
- The fail-safe yields to a new Breath/fade, overspeed warning, manual power state, or an already-running restore so it cannot fight intentional commands.
- No v90.13 repeated three-round recovery loop is reintroduced.

## v90.15.2 — Ambient diagnostic flight recorder + consensus hardening

v90.15.2 keeps the v90.10-derived BLEDIM/Lotus transport and animation pacing while making the ambient state machine observable enough for one-drive diagnosis. `AMBIENT TRACE` snapshots record engine consensus, startup state, headlight consensus, per-light connection/GATT/power/brightness, and active operation ownership at meaningful events. It also prevents duplicate BLE advertisements from perpetually restarting the 0.75-second headlight consensus window, and startup day/night classification now treats mixed Dashboard/Center evidence as unresolved and requires the final BOTH-ON/BOTH-OFF candidate to remain stable before consuming the startup Breath. See `docs/V90_15_2_AMBIENT_FLIGHT_RECORDER_AND_CONSENSUS_HARDENING.md`.


## v90.16 — field-hardened engine/headlight pipeline + one-shot BLEDIM boot settle

The v90.15.2 flight-recorder drive showed that the app-visible HUD-side OBD connection
event can remain false for an entire otherwise healthy drive. Requiring HUD + OBD2 to
both report connected therefore deadlocked ambient automation in `engine=false`,
prevented startup classification/headlight consensus, and left HUD brightness ownership
split between consensus rehydration and an older Center-only watchdog.

v90.16 keeps the field-proven v90.10 ambient packet/animation transport and corrects
those higher-level assumptions:

- **Engine ON returns to the v90.10 HUD-primary model, with a 0.75 s stability gate.**
  A stable HUD transport starts the vehicle session even if the optional HUD-side OBD
  connection event is still missing. OBD2 remains active as secondary evidence and is
  logged/corroborated when available.
- **Engine OFF is intentionally harder than engine ON.** HUD + OBD2 must both be absent,
  the direct OBD BLE witness must be absent, and the engine-powered Door controller must
  also stop providing recent power evidence before the existing OFF-confirmation timer
  may complete. A HUD-only reboot therefore does not create a false shutdown.
- **HUD auto-brightness has one owner.** After startup, only the confirmed
  Center+Dashboard two-light headlight consensus controls Auto Brightness. The watchdog
  periodically reasserts the current confirmed ON *or* OFF state; it no longer sends ON
  merely because Center is present.
- **Fresh BLEDIM controllers get one delayed boot-settle reassert.** 1.5 s after new FFF1
  GATT readiness, Door/Dashboard receive one semantic safety reassert. If no animation
  owns brightness, it is one normal `Power ON -> RGB -> preferred brightness` restore.
  If a Breath/fade is already active, only Power ON + normal RGB are reasserted so the
  animation retains brightness ownership and performs its normal final return.
- The boot-settle safeguard is event-driven and one-shot. It is not the v90.13 repeated
  recovery loop and does not add periodic ambient-light writes during normal driving.
- HUD-side OBD auto-connect remains self-healing but now backs off from 4 s retries to a
  maximum 30 s interval when no positive OBD event arrives, avoiding hundreds of
  redundant HUD UART commands in one drive.
- Courtesy suppression, stable startup day/night classification, the two-light
  Center+Dashboard consensus, animation-abort steady-state fail-safe, overspeed controls,
  Spotify vehicle wake gate, and OSM speed-limit sources remain intact.

See `docs/V90_16_FIELD_HARDENING.md`.

### v90.34.8.1 CI compile correction
The Xcode 26.6 simulator CI exposed three Swift generic-inference errors in the new minimal ADB client. v90.34.8.1 adds explicit `CheckedContinuation<Void, Error>` / `CheckedContinuation<Data, Error>` result types only; boot-animation and ADB runtime semantics are otherwise unchanged from v90.34.8.

## v90.35.3.1 relay stability

Suppresses ordinary HUD profile rehydration while the mode-6 U2W live relay is active and prevents the legacy mode-5 control from interrupting the relay. Pair with U2W v8.14.1 for persistent KivicCast rediscovery.


## v90.35.3.10.1 CI alignment

This point release contains **no runtime behavior changes** from v90.35.3.10. It only updates the stale `V90353U2WLiveFrameRelayTests.testRelayUIReportsFrameIngress` XCTest to match the intentionally compact Map Mode UI introduced in v90.35.3.10.

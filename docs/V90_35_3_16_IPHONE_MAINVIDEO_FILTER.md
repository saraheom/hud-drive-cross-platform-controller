# v90.35.3.16 — iPhone MainVideo Filter / Map-Mode-only video

## Why this release exists

Two adapter-side attempts produced different failure modes:

- **U2W v8.18** modified the AppleCarPlay process to reselect a MainVideo fd. Field testing showed the adapter repeatedly disappeared/rebooted. That architecture is retired.
- **U2W v8.19** moved filtering outside AppleCarPlay into a standalone Boa CGI, but the filter repeatedly rescanned the rolling H.264 file when no valid GOP was available. During the 2026-09-16 drive, the iPhone timed out the endpoint roughly every 16 seconds, Route Guidance/media/HUD ingress subsequently timed out, and the adapter restarted. v8.19 is therefore also retired for road use.

The stable adapter baseline is restored to:

- **MainVideo exporter:** v8.11
- **MainVideo HTTP streamer:** v8.17 LatestFrame
- **HUD JPEG relay:** v8.15.1 session-scoped relay already present in the adapter stack

No new U2W firmware image is required for v90.35.3.16. Roll back v8.19 with its uninstall image.

## MainVideo architecture

Field captures establish an important property of fd33: it is not a clean H.264-only transport. A known-good capture contains real 800×480 CarPlay H.264 mixed with unrelated/false Annex-B-looking data. Later captures can contain long spans with no valid H.264 parameter-set/slice relationship at all.

v90.35.3.16 therefore moves the expensive validation to the iPhone:

1. U2W v8.17 forwards the raw bytes with minimal adapter CPU work.
2. `AnnexBH264Parser` finds candidate NAL boundaries.
3. `H264MainVideoSanitizer` rejects a candidate unless it is structurally consistent with the validated 800×480 stream:
   - `forbidden_zero_bit == 0`;
   - SPS syntax is valid and resolves to 800×480;
   - PPS references an accepted SPS;
   - VCL slices reference an accepted PPS/SPS and have a plausible slice header;
   - continuation slices must match an already validated first slice;
   - unrelated NAL classes are dropped before VideoToolbox.
4. Only sanitized SPS/PPS/IDR/P slices reach `H264VideoToolboxDecoder`.
5. The newest decoded image remains a one-frame mailbox for the physical 5-fps HUD JPEG relay.

Reference-field validation of the Swift sanitizer:

- Known-good capture: 473 Annex-B candidates; **309 accepted** (1 SPS, 1 PPS, 1 IDR + 306 non-IDR slices), 164 rejected.
- Contaminated 73,617-byte capture: **0 accepted**.
- Latest 4.41-MB contaminated capture: **0 accepted**.

This means the app can safely extract every valid frame that is actually present. It cannot manufacture frames during a period in which fd33 genuinely carries no valid CarPlay H.264. The next road test is intended to distinguish “valid video buried among junk” from “the source itself disappears for long intervals.”

## No HTTP reconnect storm

The iOS client no longer tears down/reopens the HTTP stream merely because bytes are arriving without a decoded image.

- Fresh raw bytes + no decoded frame for 20 s: local VideoToolbox resync only; HTTP remains open.
- Local decoder resync cooldown: 30 s.
- Raw source silence: 60 s before one transport reconnect.
- Source reconnect cooldown: 60 s.
- Actual HTTP/transport completion: retry after 5 s.
- URLSession request inactivity allowance: 60 s.

This avoids the ~16-second repeated CGI churn seen with v8.19.

## MainVideo is Map-Mode-only

A second field finding was that v90.35.3.15 started MainVideo whenever HUD BLE connected. That meant the adapter continued doing video work after the user had disabled Map Mode.

v90.35.3.16 changes ownership:

- HUD BLE ready: Route Guidance/media start, MainVideo stays **off**.
- Live U2W Map Mode successfully starts: MainVideo starts.
- Live U2W Map Mode stops: MainVideo stops immediately.
- Normal Navigation/Freeride: zero MainVideo HTTP traffic.
- Manual “Reconnect U2W video” is disabled while live Map Mode is off.

## OBD 12-second probe follow-up

The 2026-09-16 probe worked at approximately 29–35 mph but returned the same non-speed payload (`03 01 01 00 00 00 06`). The second attempt around 42 mph could not start because HUD-side OBD had disconnected immediately after the first probe cleanup.

The old cleanup path explicitly cleared the custom OBD slot. v90.35.3.16 instead:

- restores fullscreen;
- sends KeepAlive;
- leaves `OBD_DRIVING_VELOCITY` configured but hidden while Map Mode remains active;
- performs one delayed health check and reconnect request if HUD OBD nevertheless drops;
- clears the diagnostic slot when Map Mode itself exits, then reasserts OBD once if that exit cleanup disconnects it.

This is diagnostic only. No production OBD speed decoder is enabled.

## U2W v8.19 rollback

While connected to the U2W Wi-Fi, verify the rollback image:

```powershell
Get-FileHash ".\\U2W_Update_v8.19_SafeMainVideoFilter_UNINSTALL.img" -Algorithm SHA256
```

Expected SHA-256:

```text
096be9abf03c1d72ba630baf2430d567ac3c12ac8de0c516e09d9fe6dc11b88d
```

Upload it:

```powershell
curl.exe -v `
  -F "file=@.\\U2W_Update_v8.19_SafeMainVideoFilter_UNINSTALL.img;filename=U2W_Update.img;type=application/octet-stream" `
  "http://192.168.50.2/cgi-bin/upload.cgi"
```

Then fully remove power from the adapter and reconnect it.

Verify the stable exporter:

```powershell
curl.exe -sS "http://192.168.50.2/cgi-bin/u2wvideo-status.cgi"
```

It should report **U2W Main CarPlay Video Live Exporter v8.11**.

Verify the HTTP streamer:

```powershell
curl.exe -sS -D - -o NUL --max-time 5 `
  "http://192.168.50.2/cgi-bin/u2wvideo-main-stream.cgi"
```

Expected header:

```text
X-U2W-Streamer: v8.17-latest-frame-generation-guard
```

## Next road test

The highest-value test is intentionally simple:

1. Confirm v8.11 exporter + v8.17 streamer before driving.
2. Start navigation normally with Map Mode **off** for several minutes; confirm audio/touch responsiveness remains normal.
3. Enable live Map Mode and leave it enabled through a useful section of the drive.
4. If the image freezes, do **not** repeatedly toggle Map Mode; leave it running so the iPhone filter counters can show whether any valid H.264 returns naturally.
5. Near the end, capture the app log, `u2wvideo-status.cgi`, `u2whud-status.cgi`, `u2wrgd-live.cgi`, and one MainVideo dump.
6. If practical, repeat the 12-second OBD probe once while HUD OBD is connected, then a second time later to verify the post-probe OBD connection remains available.

The decisive counters are shown directly in Map Mode diagnostics: raw NAL candidates, accepted/rejected candidates, validated SPS/PPS, IDRs, and slices.

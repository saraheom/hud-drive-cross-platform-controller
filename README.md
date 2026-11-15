# HUD Controller v90.35.3.24.36 — Video Recovery & Route Spotlight (experimental)

## Source base

`saraheom/hud-drive-cross-platform-controller`, `main` commit `4f7e2c030d8aacf5565ef81286ed52c8a363c439` (retrieved November 15, 2026). This distribution is a **patch plus a full-repository ZIP builder**. A GitHub App installation returned HTTP 403 on branch creation, so no remote commit or iOS build was made here.

## Changes

- Adds `Route Spotlight (experimental)` to **Map appearance** next to Follow source / Dark HUD / Light HUD. It is saved by the same settings and preset machinery as the existing three options.
- For a **high-confidence warm/yellow or saturated-blue continuous route candidate** in the CarPlay raster, suppresses other map detail and renders the selected path on black in electric cyan. Navigation, speed and music UI overlays are unaffected.
- If that shape is not confidently identifiable (e.g. a low-contrast daytime route or a busy blue road network), it **falls back to the existing Dark HUD filter** instead of drawing a false line or hiding the route.
- On decoder failure (`-12903` or sustained `-8969`), attempts read-only SPS/PPS/IDR history bootstrap **on the same healthy TCP/15332 connection**. Serializes the buffered live data to a validated snapshot/live overlap; rebuilds the decoder/reference state after overlap is proven while retaining previously validated SPS/PPS (to allow a clean IDR to recover without repeated parameter sets). Original TCP reconnect remains for real transport loss.
- Labels a snapshot/live byte overlap as `BYTE_OVERLAP_PROVEN`, not successful video recovery. Only a subsequent real decoded image establishes `LIVE`.
- Captures one post-continuity-warning decoded JPEG at most every 45s and a bounded raw H.264 evidence window. These improve root-cause comparisons with the adapter after the drive.
- Does **not** modify adapter firmware, music, ambient, HUD join recovery or speed-limit matching.

## Build full repository on Windows

1. Extract this ZIP to a directory on your Windows computer (Git for Windows and Python 3 required).
2. Open PowerShell in the extracted `HUD_v90_35_3_24_36_VideoRouteSpotlight` directory.
3. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\build_full_repo.ps1
   ```
4. Find `build-output\HUD_Controller_v90_35_3_24_36_FULL_SOURCE.zip`. To push an actual feature branch to GitHub for iOS CI, use `-Push`. This does not alter `main` directly.
5. Open a PR against `main`, run the iOS CI workflow, and only then run TestFlight.

For an **existing checkout at exactly the base SHA**, instead run `python .\apply_to_repo.py --repo "C:\path\to\hud-drive-cross-platform-controller"` and commit the five changed/new Swift files.

## Test-drive plan

1. First select Follow Source and verify live map baseline. Test phone lock/unlock, engine stop/accessory power, and restart of the physical HUD. Confirm auto Map Mode preserves the current HUD connection.
2. Test the new `Route Spotlight (experimental)` style on a **parked** car with a live navigation route. Compare it with Dark HUD under daytime and nighttime palettes. If the route is low-contrast or visually ambiguous, the image should revert to ordinary Dark HUD automatically. Distinct blue routes are also detected experimentally.
3. If map colors distort or the live map disappears again, capture the iOS diagnostic ZIP **and** the U2W `u2wvideo-relay-status.cgi`, `u2whud-status.cgi`, read-only forensic/bootstrap package, and mainvideo dump at approximately the same time. Note the time, phone lock state, navigation session and CarPlay screen changes.
4. Never switch the physical dashboard screen while moving to debug a video issue; use the parked recovery procedure only.

## Validation limitations

- The new Swift files passed Swift parser checks on Linux.
- The source patch and its markers were exercised against a synthetic source fixture; exact anchors were independently checked against the GitHub files at the reviewed SHA.
- iOS SDK / VideoToolbox rendering, real-car streaming and iOS CI **have not** been executed here. The route extractor is experimental and cannot guarantee reliable isolation of the route on every map color theme or provider.

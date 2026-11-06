# HUD Controller v90.35.3.24.35 — Auto Map Mode physical HUD restart recovery

**Source base:** `saraheom/hud-drive-cross-platform-controller`, commit
`197741e9aaaf19d895a2994091e3971d665ff992` (the source reviewed on 2026-11-05).

**Distribution:** This ZIP contains a verified source-update builder, the new
Swift policy and XCTest cases. It is **not** itself a full repository clone.
The PowerShell builder clones the pinned repository commit, applies the updates
and creates `HUD_Controller_v90.35.3.24.35_FULL_SOURCE.zip` on your computer.

## Summary

This is an iPhone-side recovery fix for the Nov 5 gas station test: BLE/HUD
power cycling while U2W remains powered, status 4 DHCP timeout, a valid
previously healthy MainVideo pipeline, and a HUD viewer that never completes
its first MJPEG handshake. The app already persisted Auto Map Mode but its
existing one-shot Wi-Fi join recovery could exhaust itself without entering
ongoing display-health monitoring.

Changes:

1. Add an independent desired-state HUD viewer reconciliation task while Auto
   Map Mode is enabled and HUD BLE is connected. Poll the actual U2W current
   MJPEG viewer session every six seconds, *including during startup*.
2. Adopt `established && session_client_seen && session_live_frame_sent` as
   actual current-session readiness, even if the stock Wi-Fi STA status reports
   4 (`Address search timeout`) or 6 (`Empty network`).
3. After a 34-second startup grace and two confirmed missing-viewer samples,
   perform a bounded HUD-only mode4 → mode6 → saved credentials rejoin. At most
   three outer retry attempts per BLE session, with a 42-second cooldown.
   Recheck the real viewer immediately before the original one-shot mode change
   too. An unavailable CGI response is treated as inconclusive, not a failure.
4. Resume reconciliation after BLE transport-ready, physical HUD session hello,
   Auto Map Mode ON, and foreground preference resynchronization. Cancel/reset
   tasks on BLE disconnect, explicit Map Mode stop, or Auto Map Mode OFF.
5. Prevent dashboard rehydration on a firmware hello while physical Map Mode
   relay is active. A mode6 command can itself produce that hello.
6. Fix an existing automatic prewarm fallback where a failed JPEG ingress
   could permanently consume a one-time automatic attempt even though the
   initial 90-second readiness window had not expired.
7. Keep U2W v8.40, MainVideo H.264 handling, music UI, ambient lighting, and
   Current+Nav speed-limit logic unchanged.

**Safety and boundaries:** This change only attempts recovery while the app
actually runs and BLE is connected. iOS can suspend background execution. It
cannot guarantee an immediate or continuous live H.264 CarPlay picture when
Apple's source has not emitted a usable IDR. The existing fallback/stock
navigation behavior remains, and the recovery budget avoids infinite mode
churn. Do not use on-road manual interactions to test it.

## Build the complete source ZIP

Unzip this package. Open PowerShell inside the package directory, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\build_full_repo.ps1
```

Requires Git and Python 3 on Windows and an internet connection for cloning
GitHub. The script creates a fresh local feature branch from the *reviewed*
commit and produces a complete source ZIP. It does not push to GitHub or
publish to TestFlight. To apply to an already clean local clone at the reviewed
commit:

```powershell
powershell -ExecutionPolicy Bypass -File .\build_full_repo.ps1 -ExistingRepo 'C:\path\to\hud-drive-cross-platform-controller'
```

To create a local Git commit (still no push), add `-CommitLocally`.

After inspection, push the created feature branch:

```powershell
git -C .\hud-drive-cross-platform-controller push -u origin fix/2026-11-05-auto-map-mode-hud-rejoin
```

Then open a PR against `main` and let `ios-ci` and the TestFlight workflows
compile and validate on Apple's macOS runner. If you instead want the patch on
`main`, merge the branch after CI passes.

## Verification performed in this environment

- `qa/check_policy.swift` with Foundation-only `HUDMapModeAutoRejoinPolicy.swift`:
  **14/14 passing** on Swift for Linux.
- `qa/static_verify.py`: Swift parser accepted injected full reconciling method;
  checks no H.264 worker or adapter relay restart in this method.
- `qa/check_patch_anchors.py`: **11 exact source transformations** and required
  postconditions passed on a synthetic source assembled from patch anchors.
- Current GitHub AppState blob and all anchor occurrences were independently
  verified with repository reads before packaging.

**Not performed:** macOS iOS app compilation, XCTest on iOS simulator, in-car
field test, and GitHub push. Do not interpret this as a verified device build.

## Field test (parked checks and passive observations)

1. Enable Auto Map Mode, verify initial Map Mode live MJPEG viewer readiness.
2. Park, turn engine off, leave U2W on accessory power, let HUD fully power down.
3. Restart engine before adapter power disappears; do **not** open the app or
   toggle Map Mode just to help it recover.
4. After BLE reconnect, note whether Map Mode displays its fallback canvas
   then live map. Driving observations should be passive.
5. Export the iPhone app log and existing U2W HUD CGI status plus v8.40 passive
   diagnostics. Check the `MAP AUTO REJOIN` markers, STA status 4/6, current
   MJPEG session, and MainVideo phase independently.
6. Repeat with a normal full shutdown (adapter power off), if safe and feasible.

This package contains no personal log files, credentials, keys or firmware image.

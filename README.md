# HUD Controller v90.35.3.24.33 — October 31, 2026

**Status: source patch prepared; iOS/Xcode on-device build not yet run.**

This is a source patch kit for the public repository
`saraheom/hud-drive-cross-platform-controller`, based on GitHub `main` at
`89a1e1c3c54d66413db19f2892e6337aa128dbc8`. The GitHub connector can read
this source, but refused creating a write branch (HTTP 403). No GitHub changes were made.

## What this build changes

### 1. iPhone live Map Mode decoder
- Treats a lock-induced VideoToolbox `-12903` as a decoder failure rather than
  authorization to close a healthy TCP socket.
- Defers in-place repair until a stable foreground return when the failure
  occurs while the phone is locked.
- Reuses the existing v8.40 **read-only previous/current snapshot fetch** and
  exact-overlap join with buffered live bytes **on the same TCP connection**.
- Resets decoder, sanitizer and Annex-B parser only after that overlap has
  actually been proven; otherwise continues bounded live-IDR fallback.
- Adds an 18-second in-place recovery cooldown and a bounded 12-second
  foreground health check before permitting the legacy worker restart.

**Limitations:** iOS may suspend execution on lock; this cannot guarantee
continuous decoding while backgrounded, and it still depends on an available
coherent recent snapshot. The current VideoToolbox/IDR fault may reoccur.

### 2. Speed-limit Current + Nav matching
- Adds `expy`/`expwy`/`expw` expansion to `expressway`.
- Allows one missing cardinal prefix in road names (`N Mascher St` vs
  `Mascher Street`) while explicitly refusing `North` vs `South` conflicts.
- If two simultaneously credible *tagged* OSM ways on the same current CarPlay
  road disagree on speed, requires **three consecutive observations** before
  accepting the candidate way change. Strong geometry transitions remain immediate.
- During pending conflicting-tag observations, the **overspeed warning is
  disabled**. This introduces no guessed speed values.
- The normal speed source and music UI are otherwise unchanged.

### 3. No adapter firmware change
The adapter's raw mirror, TCP relay and read-only snapshot endpoints are not
modified. Existing v8.40 image/firmware is retained. The optional Philadelphia
GIS/municipal source requires a separate data provenance/license/matching pass,
so no fabricated GIS coverage is introduced in this patch.

## Apply on Windows (PowerShell)

**Option A — clone a fresh repo and produce a full source ZIP:**

```powershell
Expand-Archive .\HUD_v90_35_3_24_33_patch.zip -DestinationPath .\HUDPatch
cd .\HUDPatch\HUD_v90_35_3_24_33_patch
.\build_full_repo.ps1
```

**Option B — apply to an existing clean local repo:**

```powershell
.\build_full_repo.ps1 -ExistingRepo 'C:\path\to\hud-drive-cross-platform-controller'
```

The script creates a feature branch and writes a full source ZIP in this
extracted patch directory. It does **not** push to GitHub or replace `main`.

If Windows PowerShell blocks unsigned local scripts, invoke via
`powershell -ExecutionPolicy Bypass -File .\build_full_repo.ps1`.

## Tests / validation

- The pure Swift speed-switch policy was compiled and run successfully with
  Linux `swiftc` using `qa/check_foundation_policy.swift`.
- Two XCTest cases are included for road identity and speed change confirmation.
- Exact expected source anchors were checked against GitHub's current `main`.
- The full iOS application **cannot be compiled or driven with VideoToolbox** in
  this Linux container; GitHub Actions/TestFlight and physical driving tests
  are still required.

### Driving validation

Use the unchanged v8.40 adapter. On the new app, repeat three unlock/lock cycles
with Map Mode actively displaying a live map; after each, note whether the
video resumes without manual Nissan menu swapping. The logs should contain
`INPLACE_BOOTSTRAP_BEGIN`, `INPLACE_BOOTSTRAP_REBUILD`, and a return to `LIVE`,
with no TCP open/reconnect until a verified fallback is necessary.

For speed limits, replay `Roosevelt Expy`, `N Mascher St`, and the US-1 South
40/50 mph transition. Verify `AMBIGUOUS_TAG_CHANGE` only in geometrically
ambiguous regions and that overspeed warning stays off while the switch is
under confirmation. Confirm actual posted signs independently.

No configuration changes to the music UI.

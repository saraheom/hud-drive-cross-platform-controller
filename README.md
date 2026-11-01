# HUD Controller v90.35.3.24.33 — iOS CI hotfix

## Why CI failed

The October 31, 2026 iOS CI archive `logs_111815112963.zip` shows:

- **iOS Simulator build succeeded**.
- The XCTest run executed **400 tests with three failed assertions** in
  `V90352433SpeedSwitchTests.testCardinalOmissionDoesNotConflateOppositeSignedStreets`.
- All three failures correspond to the new road-name matching rules. The GitHub
  `main` branch contains the new test but the source file
  `ios/HUDController/Vehicle/CurrentNavRoadIdentity.swift` is still the old
  implementation (legacy Git blob `9b7fb932a90706e0e6b89fd66d4c81f0e03b46ef`).
- The workflow therefore ends with `xcodebuild` exit code 65; this **is not an
  iOS compiler or code-signing error**.

## Change

This package contains **one replacement Swift source file**. It adds:

- `expy`, `expwy`, `expw` aliases to `expressway`.
- Matching when exactly one road label omits an initial cardinal direction,
  e.g., `N Mascher St` versus `Mascher Street`.
- Rejection when **both** roads explicitly specify conflicting directions,
  e.g., `N Mascher St` versus `S Mascher St`.

It does **not** modify MainVideo, the CarPlay adapter, the music UI, or speed
warning/way-switch code. The existing speed matcher's geometry, heading, and
posted speed evidence checks still apply.

## How to apply on Windows (PowerShell)

1. Extract the ZIP to any location.
2. Apply against the **same repository checkout/branch that failed CI**:

```powershell
powershell -ExecutionPolicy Bypass -File ".\HUD_Controller_v90_35_3_24_33_CI_HOTFIX\apply_hotfix.ps1" -RepoPath "C:\path\to\hud-drive-cross-platform-controller"
```

Or manually copy the included `ios/HUDController/Vehicle/CurrentNavRoadIdentity.swift`
into the corresponding path in your repository.

3. Review, commit, and push:

```powershell
cd "C:\path\to\hud-drive-cross-platform-controller"
git diff --check
git diff -- ios/HUDController/Vehicle/CurrentNavRoadIdentity.swift
git add ios/HUDController/Vehicle/CurrentNavRoadIdentity.swift
git commit -m "Fix Current+Nav road identity normalization CI tests"
git push
```

The installer verifies that the target file matches the known older revision
before overwriting it. If you've already edited that file, it refuses rather
than silently replacing your work.

## Local verification

Compiled with Linux `swiftc` and executed **15 deterministic Foundation-only
regression cases**, including the three failed CI assertions and negative
North/South and East/West tests. All passed. To repeat on a computer with Swift:

```bash
swiftc ios/HUDController/Vehicle/CurrentNavRoadIdentity.swift qa/verify_road_identity.swift -o /tmp/verify_road_identity
/tmp/verify_road_identity
```

The complete iOS/Xcode test suite was not executable in this Linux environment;
CI must be rerun after the correction is committed. This is an incremental
hotfix for your existing full repository, not a replacement full repository.

## CI success criteria

- The `V90352433SpeedSwitchTests` suite passes its two tests.
- All previously passing iOS tests stay green.
- The compiled iOS app and unrelated adapter/music/video behavior are unchanged.

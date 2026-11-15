# HUD Controller v90.35.3.24.36 — November 15 CI integration hotfix

## Confirmed CI failure

The uploaded iOS CI log `logs_118452260624.zip` shows that the app target built, but the **unit-test target failed to compile** at `V90352436RouteSpotlightAndRecoveryTests.swift:39:59` because `HudMapAppearance` has no member `routeSpotlight`. Exit code 65. The log does not show a completed test run.

Current GitHub source at commit `70591ca535f0d8fd6e42aa2f6e83a46f339cfd8c` has the new spotlight processor + its tests, but the integration edits to the following three existing files are absent:

- `ios/HUDController/Models/HudMapModeSettings.swift`: appearance enum + title.
- `ios/HUDController/MapMode/HudMapModeCanvas.swift`: rendering switch, active-route gate, and conservative Dark HUD fallback.
- `ios/HUDController/MapMode/U2WMainVideoClient.swift`: previously planned same-TCP decoder recovery and diagnostic markers. The new regression test also requires these, so fixing the enum alone is insufficient.

This package restores the missing source integrations, retaining the already committed spotlight processor and tests. No adapter image, music UI, speed-limit engine or ambient controls are changed.

## Option A: patch your existing Windows repo (recommended)

Extract the ZIP. Open PowerShell in the extracted `HUD_Controller_v90_35_3_24_36_CI_FIX` folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\apply_ci_fix.ps1 -RepoPath "C:\path\to\hud-drive-cross-platform-controller"
```

The installer verifies the **exact Git blob hashes** of the three CI-failing sources and the existing two new files. It stages and validates the entire patch before replacing any source, so an unexpected checkout safely aborts rather than overwrites newer work. It does **not commit or push**.

In your repo:

```powershell
cd "C:\path\to\hud-drive-cross-platform-controller"
git diff --check
git diff -- ios/HUDController/Models/HudMapModeSettings.swift ios/HUDController/MapMode/HudMapModeCanvas.swift ios/HUDController/MapMode/U2WMainVideoClient.swift
git add ios/HUDController/Models/HudMapModeSettings.swift ios/HUDController/MapMode/HudMapModeCanvas.swift ios/HUDController/MapMode/U2WMainVideoClient.swift
git commit -m "Fix v24.36 Route Spotlight and decoder CI integration"
git push
```

If the branch has moved and exact hashes no longer match, the installer refuses to overwrite; reconcile changes manually or build from the pinned commit using Option B.

## Option B: generate a full source ZIP and optional GitHub feature branch

```powershell
powershell -ExecutionPolicy Bypass -File .\build_full_repo.ps1
```

This clones at the pinned CI-failing commit, applies the hotfix, creates a local feature branch and a **complete repository** archive under `build-output\HUD_Controller_v90_35_3_24_36_CI_FIXED_FULL_SOURCE.zip`.

To also push the feature branch:

```powershell
powershell -ExecutionPolicy Bypass -File .\build_full_repo.ps1 -WorkDir "$PWD\build-output-push" -Push
```

The second command uses a fresh output directory to avoid clobbering the first clone. Open a PR against main and run the iOS CI workflow.

## Validation and limitations

- The CI compiler error and current GitHub source mismatch were confirmed.
- All five relevant source-file Git blob SHAs were checked against the GitHub state.
- The original v24.36 patcher's 22 source anchors and source integrity QA passed in isolation.
- The hotfix checks nine cross-file integration requirements and stages all modifications before copying them into a repo.
- Linux Swift frontend parsing detects syntax errors but **does not compile or type-check UIKit, SwiftUI, VideoToolbox, or XCTest against the iOS SDK**.
- **iOS CI and device testing have not been rerun**, and Route Spotlight remains experimental.

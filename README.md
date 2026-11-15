# HUD Controller v90.35.3.24.36 — CI regression-contract hotfix

**Confirmed from uploaded CI run:** `main@ae68a85c2ca15c1bcce484e88b0a4f5546c14866` failed at `Validate Swift source-test contracts`, **before iOS compilation**. The validator checked 1,173 assertions and found three stale expectations.

- `V90352429StartupBootstrapFullCanvasTests.swift` expects the obsolete `continuous_join=YES` diagnostic. Production correctly distinguishes `BYTE_OVERLAP_PROVEN=YES` from actual successful decoding.
- `V90352431ResourceSafeBackgroundProbeTests.swift` and `V90352432ProductionMapBackgroundETAWarningTests.swift` expect the old lock-specific log string and old literal restart argument. Production now handles -12903 and -8969 through a bounded same-TCP recovery path.
- `.github/workflows/ios-ci.yml` filters out root-level-only pushes. The fix triggers CI on **every branch push** regardless of changed path. Manual `workflow_dispatch` and the existing PR policy remain.

## One-command application and push from Windows

Extract the ZIP to a temporary folder **outside your GitHub repository**, then open PowerShell in the extracted folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\apply_and_push.ps1 -RepoPath "C:\path\to\hud-drive-cross-platform-controller" -Push
```

This script:

1. Verifies local `main` is clean and matches the correct GitHub remote.
2. Fetches and fast-forwards `main` to the verified failing revision.
3. Checks the exact source blobs and applies changes to **three existing Swift XCTest files and the actual `.github/workflows/ios-ci.yml`**.
4. Runs **the repository's full `scripts/validate_swift_test_source_assertions.py`**. If it fails, the installer restores the original files and refuses to commit.
5. Verifies exactly those four paths are modified, commits them, and optionally pushes them to `origin/main`.

To apply and commit locally **without pushing**, omit the `-Push` flag, then run `git push origin main` when ready.

**Do not add these installer scripts or ZIP to Git.** The PowerShell script commits the four actual source/workflow files, avoiding the incomplete-push mistake encountered previously.

## Scope and limitations

No production video/route-filter/music/speed-limit/ambient code changes or U2W firmware changes are made. Local patch transform checks pass. The complete static-test validator will run **on your local full checkout before a commit**. Xcode compilation and XCTest must then run through GitHub Actions on macOS and could reveal additional problems; this package resolves the failure present in the attached log, not unobserved downstream failures.

The unrestricted push trigger increases Actions usage. It does not trigger TestFlight or an App Store release.

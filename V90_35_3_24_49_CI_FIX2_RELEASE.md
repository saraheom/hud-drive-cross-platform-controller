# HUD Controller v90.35.3.24.49 — iOS CI FIX2

Based on **v24.49 CI FIX1** (Music Overlay). GitHub Actions iOS CI run **111567414187** successfully completed the Simulator build, then failed at `Run ambient-compatible unit tests`: **398 XCTest tests executed, seven XCTAssertTrue failures across six test methods**. There were no remaining Swift compiler errors in the uploaded run.

## Root cause

The seven failures were *stale source-text XCTest assertions*, introduced by the previously requested UI cleanup in v24.48. The tests expected removed descriptions/buttons or outdated labels:

- `V9021BLEDIMAnimationTestLabTests.swift:28`: removed `Preview BLEDIM Only` button; current Ambient UI retains `Preview Enabled Lights`.
- `V903522LiveIDRLaneAmbientTests.swift:35`: obsolete detailed decoder telemetry/diagnostic ZIP description.
- `V90352410IncrementalSourceAcquireTests.swift:43`: same obsolete decoder diagnostics description.
- `V90352429StartupBootstrapFullCanvasTests.swift:54,57`: obsolete `Background continuity` section label and old Auto-Lock wording.
- `V90352431ResourceSafeBackgroundProbeTests.swift:30`: removed developer-facing decoder summary label.
- `V903538MapUILayoutCalibrationTests.swift:46`: obsolete `Full-canvas 480×240 layout` label.

The relevant video recovery and ambient-light production code remain in place; the removed text does not indicate a production regression. We updated those assertions to verify the current compact UI, while retaining their other behavioral/source safety checks.

## Changes

1. Updated exactly six existing Swift XCTest files with seven corrected checks.
2. Added `scripts/validate_swift_test_source_assertions.py`: a cross-platform static preflight for *literal* Swift source-text assertions. Checks both `XCTAssertTrue` and `XCTAssertFalse`, using each test's `source(...)` targets. Dynamic/interpolated strings remain for XCTest.
3. Inserted a new `Validate Swift source-test contracts` step into `.github/workflows/ios-ci.yml` **before Xcode build** to catch this type of stale-test failure earlier.
4. Added `tests/test_v90_35_3_24_49_ci_fix2.py` regression coverage for the current compact UI, retained controls and the preflight.

**No production Swift code was modified.** The Music Overlay sliders and playback visibility, initial MLK speed-limit logic, CarPlay video, OBD, ambient-light animations, approved HUD graphics, U2W v8.40 files and saved presets remain the same as in CI FIX1. No version-number bump is necessary.

## Verification in Linux environment

- **648 Python tests passed, 1 skipped**.
- **1,173 static Swift test source assertions** matched repository source; four dynamic assertions left for XCTest.
- **235 Swift files parsed** with `swiftc -frontend -parse`.
- **8 GitHub workflow YAML files parsed**.
- Production source was verified byte-identical to CI FIX1.
- Full repository ZIP integrity validated.

**Limitation:** `xcodebuild test` cannot be run without a macOS/Xcode environment. A fresh GitHub Actions run is required to confirm all 398 XCTest cases pass and the TestFlight workflow succeeds.

## Next steps

1. Replace your GitHub repository contents with the CI FIX2 full ZIP.
2. Run **iOS CI — Ambient Test (Xcode 26)**.
3. After a green CI run, run **iOS 26 Ambient TestFlight**.

No CarPlay adapter firmware update is required.

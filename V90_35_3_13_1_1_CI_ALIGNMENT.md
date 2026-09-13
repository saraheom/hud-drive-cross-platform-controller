# v90.35.3.13.1.1 — Xcode 26 CI alignment

The iOS CI run compiled the application successfully and executed 282 XCTest cases. Two source-string regression tests failed because their expected literals were stale after the intentional v90.35.3.13 UI/MainVideo changes:

1. `V903538MapUILayoutCalibrationTests.testNavigationUIExposesBoundedTwoPixelNudgesAndStylingControls` expected the old section title `Right-side maneuver / lane calibration`; the app now labels that section `Right-side component size / spacing` because v90.35.3.13 added independent component sizes and inter-component spacing.
2. `V903539ReliabilityTests.testMainVideoFreshnessWatchdogCanRecoverFrozenCrop` expected the v90.35.3.9-era `staleFrameInterval: TimeInterval = 10.0`; v90.35.3.13 intentionally uses `decoderStaleFrameInterval = 3.0` plus `sourceStaleInterval = 12.0` so fresh H.264 bytes with no decoded image recover quickly while true source silence gets a longer allowance.

Only the two XCTest source assertions were updated. No production source file under `ios/HUDController/` changed. The paired U2W image remains v8.17 LatestFrame.

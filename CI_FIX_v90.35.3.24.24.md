# v90.35.3.24.24 CI correction overlay

Apply this overlay AFTER the v90.35.3.24.24 release overlay/full repo.
Copy the included ios folder into your existing repository root, allowing
replacement of the two files. Commit/push both files and rerun iOS CI.

## Cause
The supplied GitHub Actions log shows that the iOS simulator build succeeded.
XCTest reported 362 tests, 3 skipped, and two failed assertions in
V90352422LifecycleKeyframeDirectELMTests.swift (lines 25 and 28).
They expected the old inline speed-command declaration and a retired
coexistence_checkpoint event after v24.24 introduced the shared command
sender and production Map Mode OBD ownership.

## Changes
- Update the existing XCTest to verify the shared ASCII 010D command sender
  and current connect/probe ownership telemetry, retaining the no-reset checks.
- Verify the manual probe sends one request and retains timeout/duplicate-probe
  guards; add a separate source-contract check for production Map Mode polling,
  GPS fallback, and returning OBD ownership to the HUD.
- Correct the Vehicle page's leftover GPS-only caption to match v24.24 behavior.

App version stays v90.35.3.24.24. OBD/MainVideo runtime logic, signing,
workflows, and U2W images are unchanged. Keep the paired U2W v8.36 image;
no additional U2W update is required for this CI correction.

## Validation performed here
- 36 assertions equivalent to the updated XCTest's source checks passed.
- Existing Python source/protocol checks: 514 passed, one legacy firmware
  module skipped, executed with a standalone runner because pytest is not
  available in this workspace.
- ZIP integrity and exact payload comparison passed.
- macOS/Xcode and XCTest execution are unavailable here; rerun GitHub iOS CI
  for actual Swift compilation and simulator XCTest validation.

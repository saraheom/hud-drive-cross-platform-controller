# v90.35.3.24.6 App-Only CI Packaging Fix

This package intentionally omits the repository-level `u2w/` firmware tree.

The first app-only ZIP retained two v90.35.3.24.6 XCTest cases that unconditionally
opened v8.25 source files. GitHub Actions therefore failed with Cocoa error 260
(file not found) even though the iOS target built successfully.

This corrected app-only package changes only test/package-boundary behavior:

- `V9035246ValidatedGOPRecoveryTests.swift` skips the two U2W source-inspection
  tests when the U2W source tree is intentionally absent.
- The iOS-side v8.24/v8.25 compatibility/diagnostic test still runs normally.
- `tests/conftest.py` ignores U2W firmware/source integration modules only when
  `u2w/` is absent. In the combined/full repository those tests remain active.
- No production iOS source files were changed by this CI packaging correction.
- No U2W firmware image/source is included in this app-only ZIP.

Local validation:

- Python app-only structural suite: 355 passed.
- Swift syntax parse of the corrected XCTest: PASS.
- Confirmed `u2w/` is absent from the package.

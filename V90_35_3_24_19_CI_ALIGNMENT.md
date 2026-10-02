# v90.35.3.24.19 CI alignment

Before packaging, the complete repository test suite exposed legacy source-contract assertions
that still required historical v8.24-v8.31 wording and the superseded v24.18 recovery policy.
Those assertions were updated to validate the current invariants instead of obsolete version text.

Final local validation:
- pytest: 485 passed, 1 intentionally skipped
- Swift syntax parse: 208 / 208 files
- no stale XCTest assertions for the v24.18/v8.31 pairing markers
- git diff --check: pass

This alignment does not reintroduce early MainVideo predecode, source reacquisition, large GOP
replay, or MainVideo-driven physical Map Mode teardown.

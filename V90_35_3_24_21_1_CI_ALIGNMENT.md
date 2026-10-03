# v90.35.3.24.21.1 CI Alignment

This is a test-contract-only alignment for the v90.35.3.24.21 + U2W v8.34 paired release.

Production runtime is unchanged and continues to report v90.35.3.24.21. U2W v8.34 is unchanged; no reflash is required.

GitHub Actions exposed two stale XCTest expectations:

1. `V90352419SafeCheckpointRobustMapModeTests` still required the v8.33 runtime wording even though v24.21 correctly pairs the exact v8.31 raw relay with the v8.34 hard-bounded mirror. Legacy v8.32 `U2WH2649` compatibility remains covered.
2. `V9035247PersistentGOPInternalOBDTests` still required the retired manual 90-second HUD-internal OBD v4 UI and old parked ZIP label. v24.21 intentionally replaces that workflow with the passive whole-drive recorder and `Collect OBD Drive Diagnostic ZIP (parked)`.

Changed files only:
- `ios/HUDControllerTests/V90352419SafeCheckpointRobustMapModeTests.swift`
- `ios/HUDControllerTests/V9035247PersistentGOPInternalOBDTests.swift`

Validation after alignment:
- Python/source-contract suite: 498 passed, 1 skipped.
- Swift parse: 210/210 files.
- Production/runtime source diff versus delivered v24.21: none.

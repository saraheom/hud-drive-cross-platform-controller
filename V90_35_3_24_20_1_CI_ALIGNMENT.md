# v90.35.3.24.20.1 CI alignment

This packaging revision changes **XCTest contracts only**. Production iOS runtime sources and U2W v8.33 firmware are byte-for-byte unchanged from v90.35.3.24.20.

The GitHub Actions iOS job successfully compiled the app but failed three assertions across two legacy test files:

1. `V90352417ReferenceContinuityTests` still expected the retired v24.17 behavior where a single H.264 `frame_num` discontinuity quarantined all dependent slices until IDR. v24.20 intentionally changed this to telemetry-only; the validated frame continues to VideoToolbox and repeated `codecBadDataErr (-8969)` remains the authoritative hard-recovery trigger.
2. `V90352419SafeCheckpointRobustMapModeTests` still expected a v8.32-only wording contract even though v24.20's production pairing is v8.33 Lossless Mirror + exact v8.31 raw relay. v8.32 handshake compatibility remains supported only for backward compatibility.

Validation after alignment:
- Python regression suite: 492 passed, 1 skipped.
- Swift source parse: 209/209 files passed.
- Production source diff versus delivered v24.20: none.
- U2W v8.33 image: unchanged; no reflash required.

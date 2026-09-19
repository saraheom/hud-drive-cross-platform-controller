# v90.35.3.23.1 CI compile alignment

This is a narrow compile correction to v90.35.3.23.

GitHub Actions/Xcode 26.6 correctly reported that `U2WMainVideoTCPWorker` called
`emitDecoderState()` from the new fatal-recovery paths, but the helper itself was
not defined on that worker type. v90.35.3.23.1 adds that private helper and routes
it to the already-existing `onDecoderState?(decoder.stateSummary)` callback.

No runtime recovery policy, lane-guidance behavior, ambient-light behavior,
Map Mode rendering logic, transport protocol, or U2W v8.23 firmware is changed.

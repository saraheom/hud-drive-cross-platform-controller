# v90.18.1 — Xcode 26.6 actor-isolation fix

The iOS 26 CI build for v90.18 failed in `OriginalSpeedLimitEngine.swift` because Swift 6 inferred the local `intValue` helper as `@MainActor` from the enclosing `OriginalSpeedLimitEngine`, while a nested helper inside `Sequence.compactMap` was treated as synchronous nonisolated code.

The fix is intentionally behavior-neutral:

- move JSON scalar parsing to `private nonisolated static func philadelphiaIntValue`
- move speed validation to `private nonisolated static func philadelphiaValidSpeed`
- call those helpers from the Philadelphia GIS feature transform
- leave matching, GIS precedence, speed limits, ambient behavior, and BLE transport unchanged

A source regression test now requires the nonisolated helpers and prohibits the old nested `intValue` helper.

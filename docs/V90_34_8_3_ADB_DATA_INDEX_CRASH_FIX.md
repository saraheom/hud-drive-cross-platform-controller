# v90.34.8.3 ADB SYNC Data-index crash fix

## Field symptom

The iOS app terminated during the first custom boot-animation install attempt. The exported in-app log starts a new session immediately afterward, so it does not contain a catchable Swift error from the failed install.

## Root cause

`HUDADBClient` consumes ADB SYNC bytes with `Data.removeFirst(_:)`. Foundation `Data` does not guarantee that the resulting collection has index zero. The old little-endian decoder treated its numeric offset as an absolute `Data.Index` (`data[offset..<(offset + 4)]`). After a SYNC record had been consumed, that subscript could be outside the valid index range even though `data.count` was sufficient, causing a runtime trap rather than a thrown error.

This path is reached during upload/read-back verification, which matches the field symptom after pressing Install.

## Fix

- Decode UInt32 fields relative to `data.startIndex`.
- Bounds-check every UInt32 decode and throw `ADBError.protocolError` on truncated input instead of trapping.
- Apply the decoder to ADB packet headers and SYNC records.
- Add XCTest and Python regressions that consume a `Data` prefix before decoding.

No boot-animation path, conversion format, filesystem target, maintenance Wi-Fi command, lane-guidance behavior, or ambient-light behavior is intentionally changed.

# v90.35.3.24.7 — iOS CI alignment

The iOS 26 CI build for v90.35.3.24.7 compiled successfully and executed 334 XCTest cases. One legacy v90.35.3.24 regression assertion still expected the pre-v8.26 status text `Decoder recovery • one validated-GOP reseed`, while the v90.35.3.24.7 production client intentionally reports `Decoder recovery • one persistent-GOP reseed` for the v8.26 persistent-GOP bridge.

This alignment changes only `V903524RecentIDRSoftwareCenterGuardTests.swift` to assert the intentional v90.35.3.24.7 wording. No file under `ios/HUDController/` changes. MainVideo runtime behavior, OBD v4, ambient lighting, navigation, media, and U2W v8.26 firmware are unchanged.

# v90.35.3.24.13.1 — CI alignment only

This package keeps the **v90.35.3.24.13 production runtime byte-for-byte unchanged**.
It fixes stale iOS CI source-string regression assertions exposed by GitHub Actions run `98251133504`.

The Xcode build itself succeeded. The test phase reported 8 assertion failures across 6 test files because those tests still expected pre-v8.30 behavior/wording:

- passive MainVideo diagnostic startup on HUD BLE ready instead of v8.30 early predecode;
- relay-health version matching that omitted v8.30;
- old hard-recovery diagnostic wording rather than the v8.30 relay-aware live-IDR policy;
- old v8.27.2 automatic codec-diagnostic UI wording.

Only these files under `ios/HUDControllerTests/` were aligned:

- `V903515SafeMainVideoTests.swift`
- `V903516iPhoneMainVideoFilterTests.swift`
- `V903517OBDNetworkLaneTests.swift`
- `V903518MainVideoLaneStreetTests.swift`
- `V903523DecoderLaneAmbientTests.swift`
- `V90352410IncrementalSourceAcquireTests.swift`

No file under `ios/HUDController/` changed. U2W v8.30 is unchanged and does not need to be reflashed.

# v90.35.3.14.1 — Xcode 26 CI alignment

The v90.35.3.14 application compiled successfully in GitHub Actions and the simulator executed 287 XCTest cases. One test failed: `V903539ReliabilityTests.testRouteGuidanceTransportHoldoverDoesNotImmediatelyDropHUD`.

The failing assertion was stale. It still searched `RouteGuidanceAdapterClient.swift` for the old `transportFailureHoldoverInterval: TimeInterval = 45.0` literal. v90.35.3.14 intentionally changed the runtime policy to:

- 90 seconds for temporary transport / HTTP failures while an active route is already established; and
- 180 seconds when the U2W endpoint remains reachable with HTTP 200 but a temporarily malformed Route Guidance JSON publication cannot be decoded.

The test now asserts those two intentional constants while preserving the existing checks for `CARPLAY RGD HOLD`, first-inactive-sample suppression, and two-sample inactive confirmation.

No production file under `ios/HUDController/` changed in this CI-alignment revision. U2W v8.18 is unchanged and does not need to be reflashed.

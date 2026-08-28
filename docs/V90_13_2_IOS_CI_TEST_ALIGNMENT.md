# v90.13.2 — iOS CI regression-test alignment

The v90.13.1 iOS application target built successfully under Xcode 26, but the XCTest target failed because `V909AmbientAnimationReliabilityTests` still expected the older per-peripheral BLEDIM2 sequence implementation.

v90.13.1 intentionally switched to one app-wide rolling BLEDIM2 sequence stream to match the previously captured official BLEDIM2 iOS application. v90.13.2 updates the XCTest assertions to protect that intended behavior.

There are no runtime controller, animation, overspeed, navigation, Spotify, or vehicle-behavior changes in this revision.

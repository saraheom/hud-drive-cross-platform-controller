# v90.12.1 — iOS 26 actor-isolation compile fix

The v90.12 iOS CI run reached Swift compilation but failed in `AmbientLightMonitor.swift` because two local validity helper functions were inferred as nonisolated even though their enclosing tasks execute on `@MainActor`.

Fix:
- annotate `requestStillValid()` with `@MainActor`;
- annotate `stillValid()` with `@MainActor`;
- add a source regression assertion so these annotations are not accidentally removed.

No ambient-light, overspeed-warning, Spotify-gating, navigation, BLE protocol, signing, or workflow behavior was otherwise changed.

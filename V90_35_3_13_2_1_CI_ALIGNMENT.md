# v90.35.3.13.2.1 — Xcode 26 MainActor CI alignment

The v90.35.3.13.2 production stabilization logic is unchanged. The iOS 26 simulator CI build exposed one Swift concurrency isolation error in the nested `monitorCurrentSession` helper inside the already `@MainActor` `AppState` task. Swift 6/Xcode 26 does not infer the nested local async function's actor isolation from the surrounding `Task { @MainActor ... }` closure.

This alignment revision adds an explicit `@MainActor` annotation to that local helper. This keeps its reads/writes of `hudU2WLiveRelayActive`, `hudU2WSTAStatus`, and `LogManager.log` on the main actor and resolves all six compiler diagnostics reported by the workflow.

No MainVideo decoding behavior, U2W relay logic, Map Mode layout/settings, OBD framing logic, ambient-light behavior, route guidance, media handling, or U2W v8.17 image changed.

# v90.18.2 — iOS CI XCTest architecture alignment

The v90.18.1 app target built successfully under Xcode 26.6, and 149 of 151 ambient-compatible XCTest cases passed. The two failures were duplicate stale source-text assertions searching for a lowercase comment literal (`animation is strictly per physical/controller return`) after v90.18 capitalized that comment.

No ambient runtime behavior was changed. The two tests now assert actual implementation invariants:

- `runStartupAnimationIfNeeded` registers Sync cohort membership before BLEDIM boot settle and queues non-BLEDIM Breath directly.
- Engine/startup/headlight session state does not gate per-controller power-on animation.
- CoreBluetooth `didConnect` clears `animatedConnectionSession`, so a returning controller is eligible for a new power-on animation.

The flight recorder label is updated to v90.18.2 to make subsequent field logs unambiguous.

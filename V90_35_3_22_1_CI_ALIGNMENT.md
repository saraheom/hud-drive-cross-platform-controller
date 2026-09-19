# v90.35.3.22.1 CI alignment

This package is a CI-only correction over v90.35.3.22.

The iOS 26 CI build compiled successfully, but `V903520GOPCacheLaneGeometryTests` still asserted the retired fixed lane-arrow shaft endpoint `let bottom = h * 0.82`. v90.35.3.22 intentionally replaced that fixed geometry with the new independent `laneArrowBodyLength` control.

The regression guard now checks the production geometry actually introduced in v90.35.3.22:

- `let body = min(1.0, max(0.55, bodyLength))`
- `let bottom = h * (0.30 + 0.52 * body)`
- the existing independent maneuver-arrow checks remain unchanged.

No production Swift runtime code changed. No U2W v8.23 files changed. No adapter reflash is required when moving from v90.35.3.22 to v90.35.3.22.1.

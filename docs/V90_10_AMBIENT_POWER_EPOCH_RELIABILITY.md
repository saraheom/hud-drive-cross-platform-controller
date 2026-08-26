# v90.10 Ambient Power-Epoch Reliability

v90.10 keeps the official BLEDIM2 `FFF0/FFF1` `55 AA` protocol and changes the
runtime/state-machine behavior around it.

## Field-log findings

The v90.9 driving logs showed three recurring failure modes:

1. Critical `writeWithoutResponse` commands (Power ON, RGB, final brightness) could be
   deferred because CoreBluetooth had no write credit, but the state machine moved on.
2. The old six-second watchdog repeatedly cancelled/recreated connections to known
   vehicle lights that were physically unavailable or slow to reconnect.
3. Dashboard/Center animation re-arming still depended on a long disconnect heuristic,
   so a short real headlight OFF -> ON event often did not create a fresh Breath.

## v90.10 behavior

- Dashboard and Center Console are treated as the two witnesses of one physical
  headlight-power session.
- First positive evidence begins a new power epoch.
- Loss of both witnesses for a short debounce ends the epoch, cancels their active
  Breath state, and allows the next ON to create a new epoch immediately.
- Door day/night retargeting cancels any previous Door fade and starts from the current
  runtime brightness.
- Semantic control writes are retried/serialized rather than discarded under
  `writeWithoutResponse` backpressure.
- Known vehicle ambient connections are not forcibly cancelled by the generic six-second
  watchdog merely because physical power is currently unavailable.
- BLEDIM animation uses raw 0...255 brightness on the shared wall-clock timeline.
  Brightness zero remains distinct from an explicit Power OFF command.

# v90.13.1 — BLEDIM2 official-slider fidelity pass

This pass re-analyzes the original Apple PacketLogger trace captured from the official
BLEDIM2 iOS app on 2026-08-24 and aligns the automatic animation path with behavior
that the physical BEKEN/BLEDIM2 controllers have already demonstrated they tolerate.

## What the official app actually does

For the Door BLEDIM connection, brightness is sent as ATT Write Command (`0x52`) to
FFF1 using the recovered `55 AA ...` command `0x88`. Continuous slider motion is not a
special fade command; it is a stream of ordinary raw brightness values.

Representative captured run:

- `F6 -> 9F -> 2F -> 00` at 101, 107, and 130 ms intervals.
- `02 -> 1B -> 21 -> 24 -> 2A -> 2D -> 2D -> 2D` mostly at 99–151 ms intervals.
- `30 -> 52 -> 60 -> 6D -> 75 -> 7A -> 7E -> 81 -> 86 -> 89 -> 89` mostly at
  99–115 ms intervals.

Across the continuous portions of the captured slider gestures, median interval is
about 101 ms and mean interval is about 106 ms. This is effectively a 10 Hz output
cadence.

The trace also proves that duplicate quantized brightness values are allowed: `2D`
and `89` were each transmitted on consecutive slider callbacks with new sequence
numbers. v90.13.1 therefore does not suppress same-value BLEDIM frames at the 10 Hz
output boundary. Lotus Lantern keeps its existing duplicate suppression.

## Sequence behavior

The original capture includes multiple active ACL handles. The outbound BLEDIM
application sequence continues across those handles instead of showing a fresh fixed
sequence start per controller (for example command sequence 0x05 on one BLEDIM ACL
handle followed by 0x07 on another, followed later by 0x09 control traffic).

v90.13.1 restores one app-wide rolling BLEDIM sequence counter and does not reset it
when an individual BLEDIM controller reconnects. This matches the observed official
traffic better than the per-device counter introduced in v90.9.

## GATT traffic reduction

The field logs showed our app enumerating and reading 180A Device Information and 180F
Battery characteristics while a headlight Breath was already beginning. Those reads
are diagnostic-only and are not required for FFF1 light control.

For an already-paired BLEDIM2 device, normal reconnect now:

1. discovers only service FFF0;
2. discovers only characteristic FFF1;
3. enables FFF1 notify when available;
4. begins normal control after FFF1 is ready.

This removes the Device Information/Battery/OAD characteristic burst from the
critical reconnect/animation window. Advertisement diagnostics and parsers remain in
the project, but normal BLEDIM control no longer actively reads those standard info
characteristics.

## Backpressure and fail-safe behavior

CoreBluetooth `canSendWriteWithoutResponse` is still honored. A transient frame is
skipped rather than queued late. `peripheralIsReady(toSendWriteWithoutResponse:)`
now also wakes pending steady-state recovery so a controller that regained transmit
credit can promptly receive Power ON + normal color + target brightness.

The v90.13 rule remains: a BLEDIM controller that disconnects during an animation does
not rejoin the old animation. It returns to steady state instead.

## Deliberately not copied

The official capture contains command `0x89` with a changing two-byte payload and a
`0x92` notification response. Its payload semantics were not established, and normal
Power/Color/Brightness control is already verified without it. v90.13.1 does not send
an invented `0x89` handshake.

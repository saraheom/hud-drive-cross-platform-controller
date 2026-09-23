# v90.35.3.24.7 engineering notes

## MainVideo state boundary

The central rule is now: **v8.11 path rotation is not a codec epoch**.

A decoder epoch changes only when validated H.264 parameter sets actually change. This allows a live TCP client and its reference chain to survive the producer's bounded rolling-file replacement.

## Recovery ordering

Normal steady state:

`v8.11 -> v8.26 validator/cache -> TCP/15332 -> iPhone sanitizer -> VideoToolbox`

New/recovered client:

`persistent validated GOP cache -> current-file validated-GOP fallback -> next validated live IDR`

Decoder output stall:

`one persistent-GOP reseed -> if no frame, preserve TCP and wait fresh IDR`

Expected relay silence while waiting is never converted into an application-level reconnect. TCP/NWConnection errors remain authoritative transport-failure signals.

## Startup hysteresis

Before ten decoded frames, the iPhone uses an 8-second hard decoder-stall threshold and suppresses soft flushing. After ten frames, the established-decoder 3-second stale-output policy is restored.

This directly addresses the field event where `Live frame #1` and the old startup hard-reset occurred at the same timestamp.

## OBD v4 boundary

v4 is intentionally not a new numeric-field regression pass. v3 already excluded the accessible HUD→iPhone event stream as a useful production vehicle-speed source.

The road phase gives the HUD stock OBD subsystem repeated reason to activate its Driving Velocity path while preserving a timestamp/GPS range. The parked phase then requests the HUD's own recent OBD diagnostic archive. The archive is intentionally analyzed offline so compressed/log-structured content is not guessed at during driving.

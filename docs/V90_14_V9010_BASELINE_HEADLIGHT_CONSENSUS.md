# v90.14 — v90.10 baseline with two-light headlight consensus

## Goal
Preserve the v90.10 ambient-light method that behaved best in the vehicle while fixing its one known edge case: a headlight-fed controller can appear, begin the shared Breath, then lose physical power before the second controller has settled.

## Confirmed headlight state
Dashboard and Center are independent observations of the same physical headlight power domain:

- both ON -> candidate ON
- both OFF -> candidate OFF
- one ON / one OFF -> transitional/unknown; preserve the last confirmed state

A candidate must remain stable for 0.75 seconds before a confirmed edge is committed. Recent radio evidence is intentionally short; a stale advertisement cannot hold the circuit ON indefinitely.

## Animation admission
A confirmed ON edge creates one headlight epoch, but the shared Breath does not start until both Dashboard and Center have writable GATT control. They are then queued together on the original v90.10 shared 20 Hz timeline. A controller that reconnects later in the same already-consumed epoch receives the normal v90.10 steady-state restore rather than replaying or joining the Breath.

## What was intentionally rolled back from v90.13.x
- Center is no longer authoritative for headlight ON/OFF.
- No three-round BLEDIM steady-state safeguard loop.
- No BLEDIM-specific 10 Hz animation experiment.
- No minimal-GATT experiment.
- No reconnect-driven synthetic headlight edge.

## Independent features retained
- configurable ambient overspeed warning color, red default
- 0–5 s pulse duration, 2–3 pulses, warning brightness and speed offset
- 60-second overspeed recross cooldown
- warning disabled when no fresh speed-limit sign is available
- Spotify automatic wake gated to HUD/OBD vehicle evidence
- Current / Enhanced OSM / OSM Trace speed-limit sources
- no HERE/commercial-map dependency

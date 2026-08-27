# v90.12 — Ambient recovery, finite overspeed warning, and Spotify vehicle gate

v90.12 hardens the remaining rapid headlight ON/OFF edge cases found in the
2026-08-27 road-test log and adds the opt-in finite red ambient overspeed warning.

## Ambient-light reliability

The authoritative headlight state is still the Center/ELK-BLEDOM presence edge
used by HUD auto-brightness. v90.12 adds a generation token to all asynchronous
headlight-fed work so stale tasks from a previous physical-power session cannot
write into a newer one.

- Every authoritative headlight ON/OFF edge increments `headlightStateGeneration`.
- A headlight edge cancels the entire old synchronized Breath timeline, including
  any Door participant, so no old final write survives an OFF -> ON transition.
- If Dashboard or Center disconnects while its Breath is active/preparing, that
  light is marked to restart its Breath after reconnect even when the overall
  headlight epoch has not changed.
- Dashboard/Center reconnect restores Power ON, preferred RGB, and steady target
  brightness, then performs a delayed Power ON + steady-brightness safety reassert.
- Breath preparation is generation-protected and contains its own Power ON and
  baseline safety reassert before animation frames begin.
- Door day/night fades remain brightness-only and interruptible; a new headlight
  edge retargets from the latest successfully applied runtime brightness.
- Engine OFF still sends no automatic ambient-light Power OFF command.

The intent is that a controller can lose physical headlight power at any point in
an animation and recover cleanly when power returns, rather than remaining at a
transient near-zero animation value until a later trigger.

## Spotify automatic wake gate

Silent Spotify App Remote connection attempts remain allowed at any time, but an
automatic Spotify app switch/wake is now allowed only when vehicle evidence exists:

- HUD BLE transport connected, **or**
- OBD2 connected.

Opening HUD Controller away from the vehicle therefore does not automatically open
Spotify. Explicit user actions such as the Music shortcut or authorization controls
remain available regardless of the vehicle gate.

## Finite ambient overspeed warning

The warning is disabled by default and intentionally uses iPhone GPS speed. It is
armed only when the currently selected speed-limit matcher has produced a fresh,
live speed limit during the current session.

Trigger condition:

`GPS speed > posted speed limit + user offset`

Configuration:

- warning light: Door or Dashboard;
- offset: 0–20 mph;
- warning brightness: 10–100%;
- pulse count: 2x or 3x;
- pulse duration: 0.4–2.0 seconds per cycle.

The warning is edge-triggered. It runs only when the condition crosses from false
to true, completes the finite pulse sequence, and will not trigger again until the
speed first returns to/below the threshold and later recrosses it.

If no fresh speed-limit sign is available, no warning is permitted. A cached limit
from a prior drive cannot arm the warning.

The warning temporarily takes ownership of the selected light, switches it to red,
and animates brightness only; it never sends a Power OFF packet. Door restores the
current semantic day/night target after the warning. Dashboard warning is allowed
only while the headlight-powered Dashboard controller is physically available; a
headlight-power loss immediately invalidates that warning generation and prevents
stale restore/final writes into the unpowered controller.

## Speed-limit sources

The no-billing source selector from v90.11.1 remains unchanged:

1. Current — original HUDWAY-style OSM matcher.
2. Enhanced OSM — directional/conditional tags and continuity-aware matching.
3. OSM Trace — rolling GPS-trace map matching against the same free OSM geometry.

The warning consumes the currently selected source and is suppressed whenever that
source has not produced a fresh valid limit.

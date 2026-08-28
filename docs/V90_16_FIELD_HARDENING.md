# v90.16 — Field-hardened ambient engine/headlight pipeline

## Why this revision exists

The v90.15.2 flight-recorder field log proved three separate problems:

1. HUD transport was healthy, but the HUD-side OBD controller never emitted a positive
   app-visible OBD connection event. The strict HUD+OBD engine-ON gate therefore held
   the ambient state machine at `engine=false` for the entire drive.
2. A freshly powered Door BLEDIM controller accepted the app's initial Power/RGB/100%
   sequence at the CoreBluetooth API level, yet the physical light later remained dark
   until a manual Preview produced sustained commands and a final brightness restore.
3. An older Center-presence watchdog still sent HUD Auto Brightness ON independently of
   the new two-light consensus, while HUD rehydration could send the consensus state
   (often OFF). Two owners were competing for one HUD setting.

## Engine-state policy

Engine ON is asymmetric and latency-sensitive:

- stable HUD transport ON for 0.75 s => confirmed engine ON;
- OBD2 connected through HUD, when available, corroborates that state;
- OBD2-only evidence does not create a new engine session.

Engine OFF is conservative:

- HUD transport must be absent;
- HUD-side OBD state must be absent;
- direct OBD BLE witness must not be recent;
- Door engine-domain power evidence must be absent;
- the existing OFF confirmation interval must then complete.

This recovers v90.10's successful startup behavior without discarding OBD as a safety
signal.

## Headlight/HUD policy

After the courtesy/startup phase:

- Center ON + Dashboard ON => candidate headlight ON;
- Center OFF + Dashboard OFF => candidate headlight OFF;
- mixed evidence => preserve the last confirmed state;
- BOTH-ON/BOTH-OFF must stay stable for 0.75 s;
- only the confirmed state controls HUD Auto Brightness;
- the periodic HUD watchdog reasserts the current confirmed state, not Center presence.

## BLEDIM boot-settle policy

A new Door/Dashboard FFF1 control connection schedules one delayed reassert 1.5 seconds
after GATT readiness.

If the light is idle, the existing v90.10 reliable restore path sends:

`Power ON -> normal RGB -> current preferred brightness`

If a Breath/fade is active, only `Power ON -> normal RGB` is reasserted. Brightness stays
owned by the active animation, whose existing final write returns to steady state.

The action yields if the controller is no longer writable, is configured OFF, an
overspeed warning owns it, or a headlight-fed controller is confirmed physically OFF.

There is no periodic ambient reassert loop and no three-round recovery.

## OBD retry behavior

Missing positive OBD events no longer generate a connection request every four seconds
for an entire drive. Automatic retries remain enabled, with a bounded exponential
backoff from 4 seconds to a 30-second ceiling.

## Transport intentionally unchanged

The ambient packet path remains the v90.10 baseline:

- BLEDIM2 FFF1 `55 AA` protocol;
- per-controller BLEDIM sequence counters;
- shared 20 Hz/raw-255 BLEDIM Breath timing;
- Lotus FFF3 `7E ... EF` protocol;
- reliable semantic write helpers for Power/RGB/baseline/final brightness;
- normal v90.10 GATT discovery/diagnostic behavior.

The v90.13 BLEDIM 10 Hz/minimal-GATT/three-round recovery experiments are not restored.

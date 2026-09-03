# v90.30 — Crank stabilization and fresh-Dashboard strict synchronization

## Field failure reproduced by the September 2 stationary test

The v90.29 startup barrier itself was correct: it reached `ready=3 late=0`, emitted one shared T0, and began a 3-light Breath. Roughly four seconds after HUD transport became ready, Dashboard disconnected during the low-brightness portion of the Breath while Door and Center remained connected. The timing is consistent with the vehicle's crank/accessory transition rather than with cohort selection.

On the subsequent headlight OFF→ON, Center was treated as the only new joiner because the Dashboard CoreBluetooth session still looked connected/GATT-ready. The strict barrier therefore opened with `expected=1 roles=centerConsole` and Dashboard was classified as already active even though it was physically dark. Dashboard's stale session disconnected later, reconnected, completed GATT setup, and returned to steady state near the end of Center's three-cycle Breath.

## v90.30 rules

### Startup
1. HUD transport connection is the gate.
2. Wait 5.0 seconds for crank/accessory stabilization.
3. Open the strict Center + Door + Dashboard cohort.
4. Wait for all three to be control-ready, including BLEDIM boot settle.
5. Release one common T0.
6. If the strict startup cannot become ready within its bounded window, skip the partial animation rather than desynchronize it.

### Later headlight cycle
1. Center OFF is authoritative evidence that the headlight-fed pair has physically lost power.
2. Mark Dashboard's current BLE connection generation stale for the next headlight event.
3. Proactively cancel a lingering connected Dashboard session after Center OFF; the persistent reconnect path remains armed.
4. When Center returns, enroll Center + Dashboard as the expected headlight cohort.
5. Do not treat Dashboard as preparable until a newer physical `didConnect` generation is observed.
6. Preserve expected Dashboard membership if it disconnects while preparation is pending.
7. Wait up to 15 seconds for fresh Dashboard reconnect + GATT + boot settle.
8. Release Center + Dashboard only on a common T0. Door remains untouched if it was already active.

## Unchanged invariants

- BLEDIM uses the field-proven **Already-On Minimal** strategy.
- The Breath waveform/cycle configuration is unchanged.
- Manual Preview is unchanged.
- OBD is diagnostic/vehicle data only; it does not gate automatic ambient animation.
- v90.29 original-style Freeride profile/mode restoration is unchanged.
- v90.28/v90.29 speed-limit continuity, pending-same-limit no-blink, same-road cache, and Philadelphia diagnostics are unchanged.

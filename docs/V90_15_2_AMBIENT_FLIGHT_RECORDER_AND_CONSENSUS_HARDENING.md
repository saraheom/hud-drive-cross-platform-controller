# v90.15.2 — Ambient Flight Recorder + Consensus Hardening

This revision keeps the v90.10-derived ambient BLE transport and visual animation implementation intact. It focuses on making one vehicle test diagnostically complete and on fixing two state-machine edge cases discovered during audit.

## Runtime behavior retained

- BLEDIM2 uses the v90.10 20 Hz/raw-255 animation path.
- Per-controller BLEDIM2 sequence counters remain.
- Existing reliable Power/RGB/final-brightness writes remain.
- Courtesy-mode automatic Breath suppression remains.
- Engine ON still requires stable HUD + OBD2 agreement.
- Runtime headlight state still requires Center + Dashboard agreement.
- The v90.15.1 one-shot animation-abort steady-state fail-safe remains.
- No v90.13 repeated three-round recovery or 10 Hz/minimal-GATT experiment is restored.

## State-machine hardening

### Duplicate BLE advertisements no longer starve headlight consensus

The scanner intentionally enables CoreBluetooth duplicate advertisements. Previously, each positive advertisement cancelled and restarted the 0.75 s headlight consensus timer. A continuously advertising controller could therefore keep a stable BOTH-ON state from ever reaching its confirmation deadline.

v90.15.2 tracks the current candidate state. Repeated evidence for the same candidate does not restart the timer. Only an actual observation change restarts consensus.

### Startup classification is now three-state and stable

After the courtesy settle:

- Dashboard + Center BOTH ON -> night candidate.
- Dashboard + Center BOTH OFF -> day candidate.
- Mixed -> unresolved; keep waiting and do not consume the vehicle-start Breath.

A resolved BOTH-ON/BOTH-OFF candidate must itself remain stable for 0.75 s before startup classification commits. This prevents a brief simultaneous BLE dropout at the settle boundary from becoming a false daytime start.

## Ambient diagnostic flight recorder

`AMBIENT TRACE` records an event-driven state snapshot at meaningful transitions. It is not emitted on the 20 Hz animation frame loop.

Each snapshot includes:

- raw HUD and OBD2 engine witnesses;
- engine consensus and confirmed engine state;
- independent direct-OBD witness recency;
- startup classification complete/pending state;
- raw Center/Dashboard headlight consensus;
- confirmed headlight state, epoch, and generation;
- Door, Dashboard, and Center connection status;
- writable GATT readiness;
- logical-power evidence and advertisement age;
- configured power, runtime brightness, and preferred brightness;
- current operation ownership: Breath, prepare, fade, restore, fail-safe, warning, or idle.

Additional explicit logs identify:

- why a startup Breath is waiting;
- why a headlight Breath is waiting;
- Breath preparation failures at Power, RGB, or baseline brightness;
- shared Breath admission/start/completion/cancellation;
- fade start/completion/cancellation;
- steady restore start/completion/failure;
- one-shot fail-safe scheduling, execution, or deliberate yield to a newer operation;
- raw HUD/OBD witness changes and confirmed consensus edges.

This makes a single exported drive log sufficient to reconstruct the ambient-light state machine without relying on visual recollection alone.

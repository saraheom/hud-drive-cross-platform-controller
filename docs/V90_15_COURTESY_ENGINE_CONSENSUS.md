# v90.15 — Courtesy-safe vehicle startup and HUD/OBD engine consensus

## Goal
Prevent pre-engine courtesy lighting from consuming the automatic startup animation while making engine-session detection conservative enough that a single HUD or OBD connection glitch cannot create false startup/shutdown cycles.

## Engine consensus
The app-visible HUD transport and OBD2 connection form a three-state consensus:

- HUD ON + OBD2 ON -> candidate engine ON
- HUD OFF + OBD2 OFF -> candidate engine OFF
- mixed -> transitional/unknown; preserve the last confirmed engine state

A new engine-ON session is committed only after both ON remain stable for 0.75 seconds. A direct OBD BLE sighting is not sufficient to create engine ON; it is used only to veto a false OFF during a HUD-only reboot.

For OFF, both primary connection states must be absent. The direct OBD witness receives a 5-second acquisition window after HUD loss, followed by the existing configurable engine-OFF confirmation delay. This intentionally favors delayed shutdown over a false shutdown while driving.

## Courtesy mode
Before engine consensus is ON, Dashboard and Center may receive courtesy power, advertise, connect, complete GATT discovery, and be restored to their normal steady state. They cannot:

- create a headlight epoch;
- start or join an automatic Breath;
- consume their startup-animation eligibility.

Door is treated the same way if it becomes controllable before engine confirmation.

## Engine-start sequence
After HUD + OBD2 jointly confirm engine ON:

1. Arm one vehicle-start animation.
2. Start the existing post-engine courtesy/headlight settle window.
3. Classify the final running state using post-engine Dashboard + Center power evidence.
4. For Day, wait for Door writable GATT control and run one Door Breath.
5. For Night, require Door + Dashboard + Center to all be physically/logically powered and GATT-controllable, then queue all three into one synchronized v90.10 Breath.
6. Do not start a separate Door brightness fade during classification; the Breath owns the Door target and returns to the configured Day/Night brightness.

If a light has startup animation disabled, the same admission path restores its steady target rather than starting a separate animation.

## Runtime headlight behavior
After the startup sequence, v90.14 remains unchanged:

- Center + Dashboard both ON for 0.75 s -> confirmed headlight ON/new epoch.
- Center + Dashboard both OFF for 0.75 s -> confirmed headlight OFF.
- mixed -> preserve the last confirmed state.
- same-epoch reconnect -> one normal v90.10 steady restore, not a replayed Breath.

## Transport baseline
This change does not bring back the v90.13 BLEDIM transport experiments. BLEDIM2 retains the v90.10 20 Hz/raw-255 animation path, per-controller sequence counters, normal GATT discovery, and retry-aware semantic writes.

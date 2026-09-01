# v90.23 — synchronize newly joined lights only

## Purpose

v90.22 intentionally moved visible Breath synchronization to a headlight-level barrier, but its first implementation admitted every configured Center/Door/Dashboard role. That was too broad for the desired vehicle behavior because an already-on Door could be replayed when only the headlight-fed Center and Dashboard were newly powered.

v90.23 changes **membership**, not the Breath waveform or BLE protocol.

## Desired transition behavior

- **Door already active; Center + Dashboard join with headlights:** only Center + Dashboard synchronize. Door is not reset, prepared, or brightness-modulated by the Breath barrier.
- **Only one light joins:** only that new joiner animates; no already-active light is recruited just to create a group.
- **Cold startup with all three still joining:** Center + Door + Dashboard share one common T0.
- **A light is still boot-settling, preparing, or actively running its startup Breath when the headlight edge arrives:** it still counts as newly joining and can be re-barriered into the cold-start cohort.
- **A light has already reached steady state in the current connection session:** it is classified as already active and is left untouched.

## Membership rule

`isJoiningHeadlightTransition(_:)` treats a light as joining when any of the following is true:

1. BLEDIM boot-settle is still pending;
2. Breath preparation is still pending;
3. the light is in the active Breath set;
4. its animation task is still running; or
5. the current BLE connection session has not yet been marked as animated.

The headlight barrier builds `joiningDevices` and `alreadyActiveDevices` from this rule. Only `joiningDevices` are passed to `resetParticipantForHeadlightBarrier`, admitted into `syncCohortExpectedIDs`, or sent through Breath preparation.

## Preserved v90.22 behavior

- BLEDIM automatic/Preview Breath remains **Already-On Minimal**.
- Newly joining BLEDIM still receives its required 1.5-second boot/GATT settle before admission.
- Ready members use one common synchronized Breath timeline/T0.
- Missing/late new joiners do not block indefinitely and receive a complete independent catch-up Breath.
- Same-road/MLK speed-limit continuity and warning-freshness safeguards are unchanged.
- The v90.22 one-time Sync migration remains in place; the Sync UI toggle remains user-controlled afterward.

## Diagnostics

The flight recorder identifies this build as v90.23 and includes `syncMembership=newJoinersOnly`. Barrier-open logs include both the joining roles and `untouchedAlreadyActive` roles so in-car behavior can be verified directly from logs.

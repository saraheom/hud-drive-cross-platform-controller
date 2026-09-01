# v90.24 — Automatic Sync: Physical Joiners + Engine-Start Full Cohort

v90.24 fixes the automatic synchronization failure observed in the 2026-08-31 field log while preserving v90.23's intended **new-joiners-only** behavior for later courtesy/headlight transitions.

## Field evidence

The log separated the problem from the actual shared Breath engine because manual **Preview Enabled Lights** synchronized correctly.

### Courtesy entry

At approximately 12:58:48, Center and Dashboard were physically present while Door was not. v90.23 nevertheless pre-enrolled all three configured roles. Center immediately performed Lotus Power/RGB/baseline preparation, Dashboard required its BLEDIM GATT/boot settle, and the barrier eventually released Center + Dashboard only after timing out Door. The cohort had a common logical T0, but Center had already made visible app-driven changes before that T0.

### Initial engine start

At approximately 12:59:11, Dashboard was still active from courtesy lighting while Center and Door reappeared. v90.23 therefore classified Dashboard as `untouchedAlreadyActive` and built a Center + Door cohort. Roughly one second later the engine was positively confirmed ON, but the older architecture intentionally did not re-arm animation from engine state. Dashboard then rebooted during the crank/accessory transition, reconnected, and ran an independent catch-up Breath. The result was visibly unsynchronized three-light startup.

## v90.24 behavior

### 1. Normal courtesy/headlight edges use physical new joiners only

A configured role is no longer guessed into the cohort merely because its setting is ON. It must actually be connected/controllable or currently connecting. A short **2.0 s discovery floor** allows a peer whose CoreBluetooth callback arrives slightly later to join the same cohort without making an absent controller block the animation.

Examples:

- Courtesy powers Center + Dashboard while Door remains off → Center + Dashboard only.
- Door is already steady and headlights later power Center + Dashboard → Center + Dashboard only; Door remains untouched.
- Only Dashboard newly appears → Dashboard gets its own complete Breath.

### 2. Automatic Lotus preparation is non-visual until shared T0

For an automatic synchronized cohort, Lotus/Center GATT readiness is now sufficient preparation. The app does **not** send pre-T0 Power ON, RGB, or baseline-brightness writes. BLEDIM retains the field-validated **Already-On Minimal** preparation (also no routine pre-T0 Power/RGB/baseline writes).

The synchronized waveform is therefore the first visible app-driven animation change for every ready member. The existing terminal steady-state commit still restores the configured final Power/RGB/brightness state after Breath.

Manual Preview remains unchanged because it was the known-good synchronization reference.

### 3. Initial engine OFF→ON is a deliberate full-cohort exception

The raw HUD engine witness arrives before the stable engine confirmation. v90.24 uses that raw ON edge to reserve ownership of the crank window and suppress/supersede a provisional automatic headlight cohort before it can start visibly.

When engine ON is confirmed, a one-time startup coordinator:

1. waits at least **4.0 s** for the crank/accessory disturbance;
2. requires all enabled configured vehicle roles to be controllable;
3. requires each BLEDIM controller's GATT control to remain ready for at least **1.5 s**;
4. requires the animation/preparation pipeline to be idle;
5. requires the Center-driven headlight/night state to remain ON;
6. releases Center + Door + Dashboard on one full-cohort common T0.

The coordinator waits at most **9.0 s**. If one configured controller never becomes ready, it can fall back to the controllable startup subset rather than blocking indefinitely.

This full-cohort promotion runs **once per confirmed engine session**. Engine OFF re-arms it for the next vehicle startup. Later headlight changes remain strictly new-joiners-only.

## Unchanged behavior

- BLEDIM production strategy remains **Already-On Minimal**.
- Late genuine joiners still receive a complete catch-up Breath.
- Already-active lights remain untouched during later headlight/courtesy transitions.
- MLK / same-road speed-limit continuity from v90.22-v90.23 is unchanged.
- Overspeed-warning freshness rules are unchanged.

## Diagnostic markers

Useful v90.24 log markers include:

- `Flight recorder v90.24 ... autoSyncPrep=deferredToT0,engineStartupPromotion=fullCohort`
- `Headlight sync barrier opened NEW-JOINERS-ONLY physicalExpected=...`
- `Headlight sync barrier discovered additional physical new joiner ...`
- `Lotus automatic sync preparation readiness-only; no pre-T0 Power/RGB/brightness write ...`
- `Raw HUD ON arms engine-start sync candidate ...`
- `Engine-start full-cohort coordinator armed ...`
- `ENGINE-START FULL-COHORT opened ...`
- `ENGINE-START FULL-COHORT common T0 ready=... late=...`

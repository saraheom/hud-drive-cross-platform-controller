# v90.28 — field reliability: OBD gate, Freeride UI, and speed continuity

> **Superseded by v90.29:** the corrected field chronology showed the Freeride center UI disappeared mid-drive and was not restored by relaunching our app. v90.29 removes the periodic Freeride watchdog, restores the separate active Freeride mode with `Navigation OFF`, and changes the ambient animation gate from OBD to HUD transport. The v90.28 speed-limit refinements are retained.

## Scope

This build is a narrow follow-up to v90.27 based on the two 2026-09-02 afternoon-commute logs. It does not change the user-requested ambient animation semantics. It makes the OBD gate recover faster, restores the original Freeride HUD presentation when firmware silently loses it, removes one unused UI control, and closes the remaining one-sample MLK 25-mph stale-clear race.

## Ambient / OBD gate

The automatic Breath rules remain:

1. OBD disconnected: courtesy/headlight-connected lights stay steady; no automatic Breath.
2. First positive OBD connection: wait for Center + Door + Dashboard; only a strict 3/3 ready cohort gets common T0.
3. Later headlight ON while OBD remains connected: animate only the newly powered cohort; an already-active Door is excluded.
4. No late independent catch-up Breath. Manual Preview is unchanged.

The field log showed GPS vehicle motion for several minutes while the HUD emitted no positive OBD event. The old retry loop eventually backed off to 30 seconds. v90.28 changes the idempotent connect-request cadence to 3, 4, 5, then 8 seconds. It also preserves a last-known positive OBD gate for 15 seconds across a transient HUD BLE/session reset while actively requesting reacquisition. A positive event ends reacquisition immediately; an explicit negative event or grace expiry publishes OBD OFF.

## Original Freeride HUD UI

The decompiled original dashboard command uses the Freeride `type=0` layout with `center=Simple`; left/right are original SideWidget dashName values. The afternoon log showed no packet-level RPM failure, but reopening the app restored the missing center RPM/bar presentation after HUD rehydration resent the dashboard configuration.

v90.28 therefore:

- keeps `type=0 / center=Simple`;
- routes the generic Freeride preset through `HudOBDController.applyFreerideWidgets()`;
- reasserts that exact packet every 20 seconds while Navigation is inactive;
- never performs the Freeride watchdog while Navigation is active;
- removes the unused `Minimize widgets` toggle from Dashboard UI.

No phone-side RPM value is fabricated; the center presentation remains HUD/OBD firmware managed.

## MLK speed-limit continuity

Two field-observed MLK dropouts occurred after a same-road fast handoff had already selected a strong explicit 25-mph successor, but the speed source itself was still at confirmation 1/2. The stale timer cleared the displayed 25 during that single sample and 2/2 restored it one second later.

v90.28 treats `pending mph == current displayed mph` as display continuity. It does not refresh warning freshness and actively disables the native warning threshold while the source is pending. A changed mph still follows normal confirmation and cannot inherit the old display value as fresh evidence.

## Philadelphia Street Centerline

The v90.27 diagnostics showed successful HTTP requests but `rawFeatures=0` on every WGS84 envelope query. The layer's native spatial reference is Pennsylvania South StatePlane while it supports standard spatial queries. v90.28 sends the current WGS84 location as an `esriGeometryPoint` with a 650-meter server-side distance and requests WGS84 output. Diagnostics continue to report raw features, speed-bearing features, geometry-bearing features, and parsed segments.

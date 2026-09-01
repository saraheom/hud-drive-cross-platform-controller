# v90.25 — Integrated Ambient Fix + Speed-Limit Continuity Refinement

v90.25 keeps the complete v90.24 automatic ambient synchronization architecture unchanged and applies two narrowly scoped refinements to **Improved + Philly GIS** speed-limit display continuity based on the 2026-08-31 field log.

## 1. Same-road forward-successor handoff

The v90.22 continuity gate fixed most Martin Luther King Junior Drive way-ID transitions, but one residual dropout occurred because the continuity bonus kept an older MLK OSM way ranked first after the vehicle had physically entered the next MLK way. The old way was roughly 40 m away while the forward successor was under 5 m away and matched the full trace.

v90.25 adds a conservative successor escape hatch when the candidate:

- has the same normalized road name/ref as the confirmed road;
- is a different OSM way ID;
- is within 20 m;
- is within 20 degrees of the vehicle trace;
- matches all but at most one stored trace point;
- has an absolute score <= 2.75 and is within 1.25 of the current best score.

A same-road successor with the same explicit limit can hand off immediately. An untagged successor can preserve the existing displayed limit. As before, an explicit different speed on the same road prevents untagged continuity from masking the speed change.

## 2. Pending same-limit stale-clear suppression

A North 38th Street field sample showed a 25-mph successor at confirmation 1/2 exactly when the four-second stale timer expired. The HUD briefly cleared the sign, then restored 25 mph one second later at confirmation 2/2.

If a road candidate is already in the normal road-confirmation path and its explicit speed equals the currently displayed speed, v90.25 marks **display continuity only** while that confirmation is pending. This prevents the stale timer from blanking an unchanged number one sample before confirmation completes.

This does **not** refresh `improvedLastResolutionFresh`, does not call `applyResolvedLimit`, and therefore does not make the overspeed warning eligible from continuity alone.

## Ambient behavior

All v90.24 behavior remains intact:

- physical-new-joiner courtesy/headlight cohorts;
- readiness-only automatic Lotus preparation before shared T0;
- one-time engine-start Center + Door + Dashboard full-cohort promotion after crank/GATT settle;
- Already-On Minimal BLEDIM production behavior;
- later headlight transitions remain new-joiners-only.

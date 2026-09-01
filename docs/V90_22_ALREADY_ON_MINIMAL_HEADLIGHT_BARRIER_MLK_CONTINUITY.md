# v90.22 — Already-On Minimal + headlight barrier sync + same-road speed continuity

> **Historical behavior:** v90.22 admitted every configured light into the headlight barrier. v90.23 supersedes only that membership rule: current behavior synchronizes newly joining lights only and leaves already-active lights untouched.

v90.22 converts the successful v90.21 in-car experiments into production behavior and fixes the intermittent speed-limit blanking observed on the August 31 Philadelphia commutes.

## 1. BLEDIM production sequence: Already-On Minimal

Field testing of the six v90.21 BLEDIM strategies showed that **Already-On Minimal** removes the visible start and end blink while retaining the smooth brightness waveform.

Door and Dashboard now use that strategy unconditionally for automatic and Preview Breaths:

1. no routine Power ON preparation write;
2. no routine RGB preparation write;
3. no baseline-brightness preparation write;
4. run the Breath brightness waveform;
5. finish with the preferred brightness only.

The old strategy enum remains in source only so v90.21 persisted values and historical diagnostics can still be decoded. The in-app strategy test lab and automatic-strategy opt-in control are removed.

## 2. Vehicle-level headlight synchronization barrier

The v90.17-v90.21 sync cohort was connection-driven. A controller that was already connected before another controller completed GATT could be missing from the cohort. In practice this allowed Center/Lotus to start before Door/Dashboard or allowed only two of the three lights to share the common start.

v90.22 adds a headlight-transition barrier above the per-controller lifecycle:

- the Center/BLEDOM day/night edge remains the authoritative fast headlight signal;
- on the **OFF → ON** headlight edge, all configured, enabled Center/Door/Dashboard roles are registered as expected participants before visible Breath begins;
- already-controllable BLEDIM members can prepare immediately with Already-On Minimal;
- a newly connected BLEDIM controller retains the existing 1.5 s firmware/GATT settle;
- Lotus can become ready immediately but waits at the barrier instead of visually leading the BLEDIM pair;
- if all expected participants become ready, the barrier releases immediately;
- otherwise the barrier is bounded by the existing 3.0 s discovery window plus 1.5 s preparation grace;
- ready members share one `startSynchronizedBreathSession()` timeline and one common T0;
- truly late members are marked late and receive one complete independent catch-up Breath when they become controllable.

A one-time v90.22 migration enables synchronization on upgrade because older builds may have persisted the experimental Sync toggle as OFF. The UI still permits the user to turn synchronization off afterward.

## 3. MLK Drive speed-limit continuity

The August 31 morning and afternoon logs show the HUD repeatedly resolving **25 mph** on Martin Luther King Junior Drive and then blanking the sign when OSM way IDs changed or an adjacent MLK segment had no `maxspeed` tag. The old implementation treated an OSM way ID as the road identity. During the normal confirmation interval `fresh=0`, and the four-second stale-display timer could clear a still-valid 25 mph sign.

v90.22 separates **road identity** from **OSM way ID**.

### Same-road explicit handoff

Road names (or refs when unnamed) are normalized, including common aliases such as `Jr` → `Junior`, `Dr` → `Drive`, `Rd` → `Road`, and `Ave` → `Avenue`. If a strong trace candidate has the same normalized road identity and the same explicit posted speed, the matcher can hand off between OSM way IDs immediately instead of forcing a false stale interval.

The continuity candidate must still satisfy geometry constraints for distance, heading, trace coverage, and score. A merely nearby road with a different name does not inherit the limit.

### Same-road untagged segment

If the same named road continues geometrically but the current OSM piece has no explicit `maxspeed`, the previously established displayed limit can remain visible. This sets a dedicated `improvedDisplayContinuityFresh` state so the sign is not cleared by the four-second stale timer.

Critically, untagged continuity **does not refresh warning freshness or warning eligibility**. The overspeed warning therefore cannot be kept alive indefinitely from an inherited display-only limit. Once same-road geometric continuity is lost, the existing road-confirmation and stale-clear behavior resumes.

The flight recorder now includes `displayContinuity=0/1` in Improved Trace output and emits explicit `same-road fast handoff` / `same-road untagged continuity` decisions for field verification.

## Regression coverage

v90.22 adds dedicated Python and XCTest source-regression coverage for:

- Minimal-only BLEDIM production selection;
- removal of the v90.21 test-lab UI;
- headlight-edge expected membership;
- shared common-T0 release and late-member fallback;
- fresh-BLEDIM boot settle versus already-controllable admission;
- the one-time synchronization migration;
- normalized same-road explicit handoff;
- untagged same-road display continuity without warning-freshness refresh.

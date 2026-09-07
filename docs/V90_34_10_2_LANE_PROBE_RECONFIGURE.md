# v90.34.10.2 — Lane right-side probe reconfiguration

## Physical result from v90.34.10.1

Parked Recorded CarPlay replay with `Right probe: Navigation` produced this physical HUD result:

- the normal ETA disappeared because the right dashboard slot was replaced with the `Navigation` candidate;
- the right slot stayed visually empty;
- lane arrows continued to render in the existing center/bottom Navigation lane view, including the stock gray container.

This rules out the tested `Navigation` side candidate as a useful right-side lane renderer on HUD FW 1.1.27.

## Why NaviMini was not actually tested

The captured log showed the UI setting changing to `Right probe: NaviMini`, but there was no corresponding `Lane right-side probe → NaviMini` dashboard transmission. v90.34.10.1 stored only `laneRightSideProbeActive: Bool`; once the Navigation probe was active, `activateRightLaneWidgetProbeIfNeeded()` returned early for every other candidate.

v90.34.10.2 additionally tracks the active candidate name. If lanes are visible and the user changes Navigation ↔ NaviMini, the HUD receives a new dashboard packet immediately and the log reports `HUD LANE PROBE reconfigure ...`.

## Parked test

1. Connect the HUD over BLE while parked.
2. Set Lane Guidance to Persistent.
3. Set Lane placement to `Right probe: NaviMini` before replay, or switch to it while a replayed lane is already visible.
4. In Recorded CarPlay lane replay, send a recorded step.
5. Confirm the log contains `Lane right-side probe → NaviMini` and `HUD LANE PROBE ... right=NaviMini`.
6. Observe the physical right/ETA area.
7. Clear replayed lanes or return Lane placement to Center (stock); ETA should be restored.

The center stock lane view is intentionally retained so the test remains non-destructive and navigation state is still visible.

## Background constraint

The stock gray lane background is rendered inside HudLauncher (`#252525` rounded container). The BLE lane packet carries lane count/types only and has no background or placement parameter. This release does not replace or patch HudLauncher.apk and performs no ADB/filesystem write for lane rendering.

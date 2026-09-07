# v90.34.10.1 — Recorded CarPlay replay for the right-side lane probe

## Purpose

This build restores the parked recorded-lane replay UI specifically so the v90.34.10 right-side stock-widget experiment can be tested without driving or requiring the U2W adapter.

The following older diagnostic cards stay removed from the iOS 26 Navigation screen:

- `Ambient-light test build`
- `Manual navigation diagnostics`
- `Firmware-native lane guidance`

Only `Recorded CarPlay lane replay` returns.

## Replay path

A replay step uses the existing BLE-only path:

```text
Recorded Apple/Google 0x5204 fixture
    -> navigation.navigationOn()
    -> navigation.send(captured maneuver)
    -> setLaneGuidanceForCurrentManeuver(captured lanes)
    -> lane presentation policy
    -> optional right-side stock widget probe
```

The replay does not contact the U2W adapter, does not use ADB, and does not write the HUD filesystem.

## Quick bench test

1. Power the physical HUD and connect the custom app over BLE.
2. Open **Navigation**.
3. Set **Lane Guidance = Persistent** so distance gating cannot hide a fixture.
4. Set **Lane placement = Right probe: Navigation**.
5. In **Recorded CarPlay lane replay**, choose Apple Maps or Google Maps and tap **Send This Recorded Step**.
6. Observe the right/ETA region and the center lane renderer.
7. Tap **Clear Replayed Lanes**. The normal ETA dashboard should return.
8. Repeat with **Right probe: NaviMini**.

The decisive observations are:

- right-side lane arrows appear;
- only a maneuver appears on the right;
- right side is blank/unchanged;
- whether the right-side candidate has the same gray `#252525` background;
- whether ETA restores after clearing.

The center gray lane box can still appear during this probe because the stock lane packet is fanned to the existing Navigation renderer as well; v90.34.10.1 does not patch `HudLauncher.apk`.

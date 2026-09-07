# v90.34.10 — right-side lane renderer probe + background research

## Physical result carried forward from v90.34.9.1

The stock `HudHUDWidgetsMiniState(true)` command does not create a small side Music widget. It changes the whole HUD into the stock mini notification layout: Music occupies the upper portion and the normal dashboard is compressed below it. v90.34.10 leaves that previous experiment intact for regression purposes but moves the active investigation to lane presentation.

## Firmware findings

Static inspection of HUD FW 1.1.27 establishes two constraints that matter for this experiment:

1. `HwDriveCoreView.setLaneInstructions(List)` sends the same lane list to the current center, left, and right widgets.
2. The proven center `ManeuverViewNewLayoutWidget` draws the lane container itself and hard-codes the background with `Color.parseColor("#252525")` before `Canvas.drawRoundRect(...)`. The inactive and active lane colors are also drawn by that widget. This means the gray background is not encoded in the iPhone lane packet and is not controlled by the stored `mNavigationTheme` value.

Only the center maneuver implementations were found overriding `setLaneInstructions(...)`; ordinary side widgets inherit a no-op implementation. `WidgetUtil` nevertheless contains legacy names/resources including `NaviMini` and `widget_navigation_side`, so a physical factory probe is worthwhile before concluding that the side path is entirely dead in this firmware.

## Safe probe design

A new **Lane placement** setting appears under Navigation presentation:

- **Center (stock)** — unchanged v8.8 lane behavior.
- **Right probe: Navigation** — when lane policy says lanes should be visible, keeps the normal center `Navigation` renderer and temporarily replaces the right-side ETA widget with `Navigation`, then re-sends the current maneuver followed by the native lane packet.
- **Right probe: NaviMini** — same right-side ETA replacement, but the candidate widget string is `NaviMini`.

The center is intentionally left as `Navigation` for the physical road test so the proven maneuver display remains available. Because the stock lane command fans out to every widget, the known gray center lane box may still appear at the same time. The probe asks whether either stock right-side factory candidate *also* accepts maneuver/lane state. If it does, the next phase can focus on suppressing/rerouting the center lane layer without sacrificing the center maneuver renderer.

When lane guidance becomes ineligible, the app automatically restores the user's normal Navigation dashboard (including the normal ETA side widget) and re-sends the current maneuver. No ADB connection, APK replacement, `/system` write, or HUD filesystem modification occurs.

## Interpreting the field test

- If either right-side probe renders lane arrows, we have a viable stock side renderer and can next work on routing/hiding only the center lane graphics while preserving the center maneuver.
- If it renders only a maneuver or nothing, that confirms the recovered side-navigation resources are unused or do not implement lane instructions in FW 1.1.27.
- If neither probe can render lanes, the exact requested **right-side lanes with no gray background** cannot be achieved through the existing BLE lane/widget packets alone. The next engineering path would need a HUD-side renderer/instrumentation strategy. We should still avoid replacing the signed `HudLauncher.apk` unless we first find a reversible data-partition hook comparable to the boot-animation override.

## Log tags

Use `HUD LANE PROBE` to identify activation/restoration and `HUD LANE POLICY` for the lane packets themselves.

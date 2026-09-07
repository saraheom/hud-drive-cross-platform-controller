# v90.34.12 — UI reorganization + current-turn text control

## Scope

This release starts from v90.34.11, whose original HUDWAY **Scale** and **Perspective** controls were physically confirmed working. v90.34.12 does not change those display-calibration packets or the existing boot-animation safety boundary. It reorganizes the normal UI and adds one app-side maneuver-text presentation preference.

## Navigation presentation

A persisted **Show Current Turn Text** toggle sits immediately below **Show Current Street**. It defaults ON. When OFF, `HudNavigationController` copies the current `NavigationInstruction` and blanks only `wireInstruction.primaryText` before sending the native maneuver packet. The source instruction is left intact. Maneuver type/direction, upcoming street, current street (subject to its own toggle), distance, exit number, ETA, and lane guidance are unchanged.

The native HUDWAY maneuver packet has one UTF field containing the presentation lines. To keep field positions stable when the first line is hidden, `HudCommands.maneuver` now removes only empty **trailing** lines and preserves leading/interior empty lines. Thus a hidden first label is encoded as:

```text
\nUpcoming Street
Current Street
```

rather than shifting `Upcoming Street` into line 1.

## Removed experimental UI

The iOS 26 Navigation page no longer exposes:

- Recorded CarPlay lane replay;
- the physically disproven right-side `Navigation` / `NaviMini` lane-placement picker;
- older manual/firmware-native diagnostic cards.

The Media page no longer exposes the Persistent stock Music renderer experiment. Live CarPlay Route Guidance, native lane presentation, ETA, and passive CarPlay Now Playing remain unchanged. Historical replay/music backend code remains in the repository for regression/reference only. Any persisted right-side lane placement is migrated to `.centerNative` on settings initialization.

## App navigation reorganization

The persistent top strip is now:

`Navigation | Music | Ambient | My Trips icon | Settings icon`

The three original quick actions remain rectangular. My Trips and Settings are compact icon buttons; My Trips opens the existing Trips & Logs view as a sheet.

The five bottom tabs are now:

`Navigation | Dashboard | Media | Vehicle | Ambient`

Ambient replaces the former My Trips tab.

## Ambient / Vehicle split

All light-specific controls now live in Ambient, including:

- BLE ambient-light connection and paired devices;
- smooth brightness transitions and Breath animation;
- Door day/night behavior;
- light groups and presets;
- Center/BLEDOM-driven HUD Auto Brightness;
- finite ambient overspeed-warning light, color, offset, day/night brightness, pulse count/duration, and cooldown.

Vehicle retains OBD-II state and the speed/speed-limit engine. The speed-limit source selector remains there; Ambient consumes the resulting posted-speed/warning-eligibility state rather than owning map/GIS matching.

## HUD color labels

The historical `HudColorTheme.rawValue` names and `originalWireValue` mappings are deliberately unchanged. A separate `displayName` is used for the visible UI so swatch labels describe the colors actually rendered by the HUD. In particular, the first three physical swatches are shown as **Blue / Red / Green** rather than the misleading original enum labels **Red / Green / Blue**.

## Collapsible explanatory text

Primary cards use the reusable `HudDescription` component. A **Details** control with up/down chevron hides or restores explanatory prose. The actual setting controls and live state stay visible so collapsing help text never prevents changing a setting.

## Safety

This UI release adds no new firmware writer, ADB command, `/system` modification, APK replacement, updater action, or unknown BLE command. The new turn-text toggle changes only the existing maneuver UTF payload. Scale/Perspective remain the validated stock BLE packets from v90.34.11.

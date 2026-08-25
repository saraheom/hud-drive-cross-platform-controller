# v90.8 — simplified ambient state machine, smooth breath, presets and shortcuts

## Scope

v90.8 deliberately separates physical vehicle-state inference from light animation.
The verified Lotus Lantern and BLEDIM2 packet adapters do not change.

## Vehicle-aware Door brightness

The vehicle state machine now has one lighting responsibility only:

1. Engine-power session must be ON (HUD transport and/or the calibrated independent
   OBD BLE witness).
2. Pre-engine courtesy-headlight advertisements are ignored during the existing short
   post-engine settling window.
3. While the engine session is ON:
   - Dashboard **OR** Center Console present => Night => Door night target.
   - both headlight-fed lights absent => Day => Door day target.
4. A Day/Night Door target change uses the same smooth brightness-transition duration
   as manual brightness changes.
5. Engine OFF sends **no** automatic ambient-light power or brightness write. All
   lights are left at their current level until the vehicle removes or changes their
   physical power.

The independent OBD witness remains necessary because a thermal/reboot outage of the
physical HUD must not be mistaken for engine shutdown.

## Smooth brightness transitions

`brightnessTransitionSeconds` is user-configurable from 1 to 15 seconds. Manual
single-light brightness, group brightness, and automatic Door day/night brightness all
flow through one `transitionBrightness` implementation.

The transition uses a shared 20 Hz timeline for all members in a group. Intermediate
runtime values are not serialized to UserDefaults on every frame; only the final
runtime value is persisted.

## Power-up Breath

There is one supported animation type. If a light's **Animation on power-up** toggle
is enabled, a fresh physical BLE/power session or a manual OFF -> ON runs:

`current -> 0% -> 100% -> current`

That path is one Breath cycle. The user selects 2x, 3x, 4x, or 5x repetitions and a
1-15 second **total** duration for the complete animation.

Brightness legs use half-cosine easing rather than hard linear corners. Lights that
become writable together are collected for 350 ms and then run on one 20 Hz clock.
A controller that becomes GATT-ready after the animation has started joins the current
phase. BLE writes are necessarily serialized by iOS, so packet transmission cannot be
truly simultaneous, but the lights share the same computed frame/phase and should be
visually close to synchronized.

A transient BLE disconnect does not re-arm Breath immediately. The existing 15-second
disconnect rule is retained to prevent an animation replay during brief radio dropouts.

## Five color presets

Every paired light has five persistent preset slots, and every group has its own five
persistent preset slots. Existing saved JSON remains backward compatible because the
preset arrays are optional and default to five built-in colors when absent.

- Tap: apply the preset.
- Long-press: save the current color-picker value into that slot.

Group preset application fans the color out through each member's protocol adapter.

## Nearby list

The general Nearby BLE Devices list is hidden from the normal Ambient Lighting UI.
Scanning, discovery, known-device reconnection, GATT maintenance, the HUD brightness
presence trigger, and the independent OBD witness continue to operate internally.

## Persistent quick actions

`RootView` owns a compact top strip on every main tab except My Trips/Logs:

- Navigation: selects Navigation, enables HUD navigation, and requests the iOS 27
  full-display picker when that capture implementation is available.
- Music: selects Media; if authorization is missing, starts authorization, otherwise
  wakes Spotify and resumes App Remote without clearing the saved token.
- Ambient: selects Vehicle and sends a focus token that navigates directly to Ambient
  Lighting and scrolls to Paired Lights.

The temporary iOS 26 ambient TestFlight flavor intentionally has no ScreenCaptureKit
implementation, so its Navigation shortcut can arm HUD navigation but cannot present a
capture picker. The normal iOS 27 build uses the real picker.

## BLEDIM2 capture provenance correction

The official BLEDIM2 PacketLogger/sysdiagnose sequence used to recover `55 AA` FFF1
Power/RGB/Brightness was performed with the **Dashboard** BLEDIM controller
(`7A3B5F81...5F81`). v90.7 field testing later confirmed the same recovered protocol
works on the Door BLEDIM controller (`FBD8C9A0...C9A0`).

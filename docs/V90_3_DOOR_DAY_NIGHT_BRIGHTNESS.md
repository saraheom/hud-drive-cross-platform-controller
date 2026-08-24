# v90.3 — Door Day/Night Brightness Automation

## Physical model

- Door (`FBD8C9A0…`) is powered whenever the engine-switched/retained vehicle
  circuit is active.
- Dashboard (`7A3B5F81…`) is powered by the headlight circuit.
- Center Console (`ELK-BLEDOM`) is powered by the headlight circuit.

Therefore either headlight-fed controller is an independent witness that the car
is in the nighttime/headlight-on lighting state.

## Targets

The user can set:

- Door daytime brightness: 0–100%
- Door nighttime brightness: 0–100%

Defaults are 100% day and 45% night. Values are persisted independently of the
door device's generic manual preferred brightness.

## Automatic transitions

- Day startup: Door pulses and settles at day target.
- Night startup: all powered lights pulse together; Door settles at night target.
- Headlights OFF → ON while driving: Dashboard/Console fade in; Door fades from
  its current value to night target.
- Headlights ON → OFF while driving: once both headlight-fed controllers are
  absent, Door fades back to day target.
- Engine OFF: the v90.2 engine-power logic still fades all powered lights to 0.
  No preferred/day/night target is overwritten.

The Door transition uses the existing `Headlight join fade` duration.

## Redundancy / hysteresis

`headlightPowerPresent()` is true when either `.dashboard` or `.centerConsole`
is logically powered. `isLogicallyPowered` already combines GATT connection with
a recent-advertisement window, so a brief single-controller BLE gap does not
immediately toggle the Door. As long as either headlight-fed light remains
present, night mode remains active.

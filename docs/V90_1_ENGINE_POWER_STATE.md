# v90.1 Engine Power State

The car's physical HUD and OBD2 adapter are both powered from the same engine-switched fuse.

## Signals

- HUD transport ready: immediate positive engine-power signal.
- OBD connected through HUD: corroborating positive signal.
- HUD transport disconnected: removes the HUD positive signal.
- OBD disconnected/unavailable: removes the OBD positive signal.

## OFF debounce

Engine OFF is committed only when both positive signals remain absent for the user-selected confirmation interval (default 2.0 seconds). Any positive signal during the interval cancels the candidate. This prevents a normal CoreBluetooth timeout/reconnect from running the shutdown animation while driving.

## Lighting actions

A confirmed OFF transition automatically invokes the same fade-to-zero routine as the manual Fade Out Now diagnostic. The routine changes only runtime/last-applied brightness; preferred brightness and color remain unchanged for the next startup.

A new HUD/OBD positive transition after confirmed OFF clears the shutdown latch and arms a fresh day/night startup classification.

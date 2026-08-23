# v90.2 HUD-only outage protection

The vehicle's HUD can occasionally power-cycle from heat or another fault while the engine remains running. The OBD2 adapter is powered from the same engine-switched fuse but remains physically powered during a HUD-only outage.

v90.1 could not distinguish those conditions because the OBD connection state is reported through the HUD; when the HUD transport disappeared, `HudOBDController.transportDisconnected()` cleared the local OBD state too.

v90.2 changes the rule:

- HUD transport present => engine power ON immediately.
- HUD transport loss alone NEVER confirms engine OFF.
- The ambient CoreBluetooth scanner also watches for the configured OBD name (default `OBDII`).
- With the engine running, switching only the HUD off once lets the app learn/calibrate the OBD adapter's iOS CoreBluetooth UUID if the adapter is BLE and resumes advertising after its HUD-side link drops.
- During later HUD-only thermal/reboot outages, recent direct OBD advertisements keep engine power ON and cancel shutdown.
- Automatic engine-OFF/shutdown fade is permitted only after that independent OBD witness has been calibrated, the HUD is absent, the OBD witness does not appear through the acquisition window, and the normal engine-off confirmation delay also expires.
- If the OBD adapter is Bluetooth Classic or otherwise invisible to CoreBluetooth, automatic shutdown remains inhibited rather than making an unsafe inference. Manual `Fade Out Now` remains available.

This deliberately favors avoiding a false shutdown animation while driving over aggressive engine-off inference.

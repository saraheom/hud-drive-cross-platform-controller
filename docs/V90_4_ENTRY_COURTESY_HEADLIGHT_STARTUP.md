# v90.4 — Entry courtesy-headlight-aware startup classification

The vehicle powers the Dashboard and Center Console ambient-light controllers from the headlight circuit. When the driver first enters the car, the car temporarily powers that headlight circuit regardless of daylight, while the Door ambient controller and the HUD/OBD engine-switched domain are still off.

Therefore pre-engine Dashboard/Center Console presence is **not** evidence of a night start.

v90.4 anchors classification to the engine-power transition:

1. Before engine power: headlight-fed presence is ignored for day/night classification.
2. HUD/OBD engine power appears and the Door circuit powers.
3. The app moves currently controllable role lights to 0 and waits the configurable **Post-engine headlight settle window**.
4. Startup is **Night** if either headlight-fed controller is still actively connected, or has produced a fresh advertisement after engine power appeared.
5. Startup is **Day** if both headlight-fed controllers have lost power by the end of the settle window.
6. Day startup pulses Door only and finishes at Door Day brightness.
7. Night startup pulses the available powered role lights together; Door finishes at Door Night brightness and the other lights at their preferred brightness.

The normal driving detector remains more tolerant: Dashboard OR Center Console logical presence means Night, with the existing BLE hysteresis, so brief radio dropouts do not brighten the Door while driving.

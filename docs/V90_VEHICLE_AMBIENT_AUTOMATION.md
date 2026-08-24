# v90 — Vehicle-aware ambient lighting + BLEDIM2/CB01 control test

> **v90.5 protocol correction:** The experimental BLEDIM `7E FF ... EF` frames documented below were physically tested on both paired BLEDIM2-compatible controllers and produced no color/brightness/power change. They are retired and must not be used. The verified transport is FFF0/FFF1, but the command payload still requires an official-app capture. See `V90_5_BLEDIM_PROTOCOL_RECOVERY_AND_SHUTDOWN.md`.


This phase keeps the temporary Xcode 26 / iOS 26-SDK build path so ambient
lighting can be tested while the Xcode 27 hosted runner is still pending.
ScreenCaptureKit navigation remains excluded only from the temporary project.

## Physical roles from the 2026-08-23 car test

The role is editable in the Ambient Lighting UI, but v90 migrates the three known
CoreBluetooth UUIDs automatically:

- `FBD8C9A0-E75E-D5FA-A1E5-E61195E6BF97` → **Door light**
  - BLEDIM2/CB01
  - vehicle / retained-accessory powered
- `7A3B5F81-E1DA-C93A-47F1-EA39C970241F` → **Dashboard light**
  - BLEDIM2/CB01
  - headlight-circuit powered
- `51FA23D6-A781-F5EB-D750-6B2C2EC9EF83` → **Center console light**
  - Lotus Lantern / ELK-BLEDOM
  - headlight-circuit powered

## BLEDIM2 test adapter

Both BLEDIM units exposed the same application path in the physical log:

- service: `FFF0`
- characteristic: `FFF1`
- properties: `writeWithoutResponse + notify`

v90 therefore enables the common CB01/BLEDIM 9-byte packet family on FFF1:

- ON: `7E FF 04 01 FF FF FF FF EF`
- OFF: `7E FF 04 00 FF FF FF FF EF`
- RGB: `7E FF 05 03 RR GG BB FF EF`
- brightness: `7E FF 01 XX 00 FF FF FF EF`, `XX=0..100`

This payload family is intentionally marked **experimental** because BLEDIM2
1.960 is Jiagu-packed and its actual Java/native command generator could not be
recovered statically. Every BLEDIM TX is logged with `[EXPERIMENTAL CB01]` so a
physical test can validate or correct the dialect without ambiguity.

The unrelated TI-style `F000FFC0... / FFC1 / FFC2` service is not selected for
light control.

## Vehicle-aware state machine

Vehicle automation is opt-in and defaults OFF after upgrade.

### Day startup

1. Door light becomes powered/present.
2. Start a configurable day/night classification window (default 4 s).
3. No headlight-fed light appears in that window.
4. Door light is forced to 0, then performs the configured 1x/2x pulse.
5. It finishes at its **preferred brightness**.

### Night startup

1. Door light becomes powered/present.
2. During the classification window, either headlight-fed controller is also
   present.
3. All currently powered/controllable role lights are prepared at 0.
4. They perform the configured 1x/2x pulse synchronously.
5. Each light finishes at its own preferred brightness.

If one headlight-fed controller becomes BLE-control-ready a little later, it is
folded into the headlight-join path instead of replaying an independent startup
pulse.

### Headlights turn ON while driving

After a daytime startup, an OFF→ON headlight-power transition is coalesced for
one second so the dashboard and console controllers can arrive together. Newly
powered headlight-fed lights are set to 0 and fade to their preferred brightness
over the configured **Headlight join fade** duration.

### Headlights turn OFF while driving

No fake fade-out is attempted. Once the car removes electrical power, BLE can
only observe the disappearance after the fact.

### Shutdown test

The current HUD↔OBD transport reports OBD connection state and supported PID
masks but does **not** stream live engine RPM back to the iPhone. v90 therefore
does not infer engine shutdown from HUD/BLE disconnects, which have already been
observed transiently while driving.

The UI provides **Fade Out Now** as the test-phase trigger. It fades every
currently powered/controllable role light to 0 while preserving:

- preferred color;
- preferred brightness;
- logical power-on preference.

The persistent model deliberately separates:

- `brightness` = user preferred steady-state target;
- `lastAppliedBrightness` = last runtime command, which becomes `0` after the
  shutdown fade.

A future trustworthy engine-state input can call the same
`fadeOutForVehicleShutdown()` path automatically without changing the animation
implementation.

## Stock HUDWAY speed-warning audit

No speed-warning command behavior is changed in v90.

The current implementation continues to match the re-audited HUDWAY Drive 1.4.6
**default Automatic/tolerance=0 semantics**:

- legal speed-limit display: command `(2,101,2)`, rectangular style, tolerance 0;
- warning threshold: `DisplaySpeedWarningCommandPacket (2,9,9)`;
- threshold value = posted legal speed limit exactly.

The 2026-08-23 field log confirms, for example, a 25 mph sign followed by a
25 mph warning-threshold packet and a 35 mph sign followed by a 35 mph threshold.

However, the user's physical HUD did not show the remembered small orange
threshold tick even though the speedometer itself changed to the orange warning
state. That means **threshold semantics are stock, but exact visual renderer
parity is not yet established**. v90 intentionally does not perturb the working
warning packets. The marker should be investigated as a separate stock HUD
initialization/rendering question.

## Recommended first physical test order

Because the BLEDIM2 payload dialect is the only experimental portion, validate it
while parked before enabling vehicle-aware automation:

1. Leave **vehicle-aware automation OFF**.
2. Open each BLEDIM device page and verify Power, a low brightness change, then
   Red / Green / Blue individually.
3. If either controller behaves incorrectly, stop there and export the HUD log;
   every FFF1 write is labeled `[EXPERIMENTAL CB01]`.
4. Once both controllers respond correctly, verify their roles (Door / Dashboard),
   enable vehicle-aware automation and use **Preview Current Startup** while parked.
5. Use **Fade Out Now** to validate the shutdown fade and confirm that
   **Preferred brightness** is unchanged while **Last applied brightness** reaches 0.
6. Only then test real daytime startup, headlight join, and nighttime startup.

The automation defaults OFF after upgrade so an unvalidated BLEDIM dialect cannot
start sending commands merely because the app reconnects in the car.

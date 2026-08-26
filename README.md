# v88 TestFlight — restore existing GitHub secrets

The previous replacement workflow accidentally referenced a new secret naming
scheme (`P12_BASE64`, `PROFILE_BASE64`, etc.). The repository already had a
working TestFlight secret set, so those values resolved to empty strings.

This patch restores the existing secret names:

- IOS_CERTIFICATE
- IOS_CERTIFICATE_PASSWORD
- IOS_MOBILE_PROVISION
- APPLE_DEVELOPMENT_TEAM
- APPLE_API_KEY_ID
- APPLE_API_ISSUER
- APPLE_API_PRIVATE_KEY_BASE64
- SPOTIFY_CLIENT_ID

No new secrets are required.

The bundle identifier is derived directly from the App Store provisioning
profile, so `HUD_BUNDLE_ID` no longer needs to be a repository secret.

The workflow also validates all required existing secrets before installing
tools or trying to sign the app.

This fixes the latest failure:
`SecKeychainItemImport: Unable to decode the provided data`

It does not alter any v88 application source code.

Note: after signing/archive is restored, App Store Connect may still return
90534 if Apple's server continues rejecting the Xcode 27 beta 4 toolchain.
That is a separate external toolchain issue.

## v89 — direct ambient-light control foundation

v89 expands the existing ELK-BLEDOM presence monitor into a single multi-device
CoreBluetooth subsystem. The existing BLEDOM → HUD Auto Brightness behavior is
preserved, but it is now independently switchable from direct ambient-light
control.

### Lotus Lantern / ELK-BLEDOM

The supplied Lotus Lantern 6.5.08 decompile exposes its BLE implementation. v89
implements that protocol directly:

- GATT service: `FFF0` (`0000FFF0-0000-1000-8000-00805F9B34FB`)
- write characteristic: `FFF3` (`0000FFF3-0000-1000-8000-00805F9B34FB`)
- power ON: `7E 04 04 01 00 01 FF 00 EF`
- power OFF: `7E 04 04 00 00 00 FF 00 EF`
- RGB: `7E 07 05 03 RR GG BB 10 EF`
- brightness: `7E 04 01 XX FF FF FF 00 EF` where `XX` is 0–100

The app restores the saved color, brightness and power state after connection.
It can also play a software-generated startup pulse: fade up/down once or twice,
then fade back to the saved target brightness. A 15-second disconnect threshold
prevents a momentary BLE dropout from replaying the startup animation.

### Pairing and groups

The Ambient Lighting page supports:

- discovery of named and unnamed BLE peripherals;
- persistent user names for lights;
- remembered CoreBluetooth peripheral identifiers;
- independent automatic reconnection;
- app-level groups containing any subset of paired lights;
- membership of one light in multiple groups;
- group power, color and brightness fan-out through per-device protocol adapters.

The two unnamed BLEDIM2-compatible lights can therefore be placed in their own
group without including the ELK-BLEDOM controller.

### BLEDIM2 protocol status

The supplied BLEDIM2 1.960 APK is protected with the Jiagu/360 packer. Its
visible DEX contains the protection loader and references such as `libjiagu.so`
and `libjgdtc.so`; the real BLE command builder is not present in JADX output.

v89 intentionally does **not** guess BLEDIM2 write packets. It already supports
BLEDIM2 discovery, pairing, automatic reconnection, grouping, and complete GATT
service/characteristic fingerprint logging. Once one BLEDIM2 Bluetooth HCI
capture is supplied, the final adapter can be added without changing the UI,
group model, or connection architecture.

## v89 temporary iOS 26 ambient-light TestFlight flavor

A parallel Xcode 26 build flavor is included for testing Ambient Lighting while
the Xcode 27 GitHub preview image is unavailable/incompatible. Run the GitHub
Actions workflow **Build and Upload iOS 26 Ambient TestFlight**. It compiles
with `ios/project-ios26-ambient.yml`, which excludes the iOS 27
ScreenCaptureKit implementation but keeps the v89 ambient-light subsystem and
the rest of the HUD controller. See `docs/V89_IOS26_AMBIENT_TEST.md`.

## v90 — vehicle-aware ambient lighting + BLEDIM2/CB01 test control

v90 builds on the iOS 26 ambient-test branch and adds the physical car-light
state machine documented in `docs/V90_VEHICLE_AMBIENT_AUTOMATION.md`.

Highlights:
- enables experimental BLEDIM2/CB01 control on the physically observed
  `FFF0/FFF1` GATT path;
- auto-migrates the known Door, Dashboard and Center Console controller roles;
- day startup pulses the Door light only;
- night startup pulses all powered role lights synchronously;
- later headlight activation fades in Dashboard + Center Console together;
- shutdown test fades active lights to runtime 0 without overwriting preferred
  brightness;
- preserves the Xcode 26 temporary CI/TestFlight path and the reserved monotonic
  TestFlight build-number range;
- leaves the stock-default Automatic speed-warning packet behavior unchanged;
  the missing physical orange threshold tick remains a separate visual-renderer
  audit item.

v90 final test packaging also keeps late GATT readiness eligible for the normal
headlight-join fade and avoids persisting UserDefaults on every intermediate fade
frame; only final runtime brightness states are committed.


## v90.1 — engine-switched HUD/OBD power state

The physical HUD and OBD2 adapter in this vehicle are both hardwired to an
engine-switched fuse. v90.1 therefore uses that power domain directly instead of
requiring a live RPM PID:

- HUD transport ready => engine power ON immediately;
- OBD connection through the HUD => corroborating engine power ON;
- HUD transport lost + OBD unavailable => engine OFF candidate;
- both signals must stay absent for the configurable confirmation delay (default
  2.0 s) before engine OFF is committed;
- any HUD/OBD recovery during that window cancels the candidate as a transient BLE
  dropout;
- confirmed engine OFF automatically runs the existing fade-to-runtime-0 shutdown
  path without changing preferred brightness.

The manual **Fade Out Now** control remains for stationary diagnostics. Vehicle
startup classification now requires engine power ON plus the door/headlight light
presence pattern, so an ambient-light reconnect by itself cannot create a false
new driving session.

## v90.2 — HUD thermal/reboot protection with independent OBD witness

- A HUD BLE disconnect by itself no longer counts as engine OFF.
- HUD-side OBD link state is cleared on HUD loss for UI correctness, but that event is no longer emitted as physical OBD power loss.
- The existing ambient CoreBluetooth scan watches the configured OBD name (`OBDII` by default) and can learn its iOS UUID when the HUD is deliberately switched off while the engine remains running.
- Once calibrated, direct OBD BLE advertisements veto shutdown during HUD-only overheat/reboot outages.
- Automatic shutdown is inhibited until the independent OBD witness is calibrated. If the OBD adapter is Bluetooth Classic and cannot be observed by iOS, the app refuses to infer engine OFF and keeps `Fade Out Now` as the safe manual path.

## v90.3 — automatic door day/night brightness

The door controller is powered for the entire engine session, so v90.3 gives it
two independent vehicle-automation brightness targets:

- **Door daytime brightness** (default 100%)
- **Door nighttime brightness** (default 45%)

Night/headlight state is redundant: either the Dashboard light **or** the Center
Console/BLEDOM light being logically powered is sufficient to select the night
target. Day returns only after both headlight-fed controllers are absent.

The door transitions use the existing Headlight join fade duration. At a
daytime startup the door pulse ends at the daytime target. At a nighttime
startup its synchronized pulse ends at the nighttime target while Dashboard and
Center Console end at their own preferred brightness. If headlights turn on
later while driving, Dashboard/Console fade in while Door fades to its night
target. If headlights later turn off and both headlight-fed lights disappear,
Door fades back to its daytime target.

These day/night values are separate from the door device's generic/manual
preferred brightness and only update runtime/last-applied brightness. Engine
shutdown still fades all powered lights to 0 without destroying any preferred
or day/night target.

All v90.2 HUD-outage protection and independent OBD witness logic is retained.

## v90.4 — courtesy-headlight-aware engine startup

Vehicle-entry behavior was corrected: Dashboard + Center Console can be powered by courtesy headlights before the engine starts in both daylight and darkness. v90.4 therefore ignores pre-engine headlight-fed presence for startup classification. Once engine-switched HUD/OBD power appears, the app waits the configurable post-engine settle window. If the headlight-fed pair turns off, the startup is Day and only Door pulses to its daytime target. If either remains powered, the startup is Night and the available role lights pulse together, with Door ending at its nighttime target.

## v90.5 — retire invalid BLEDIM packets + corrected arrival/courtesy shutdown

Field testing proved that both BLEDIM2-compatible controllers accept the BLE
connection and expose `FFF0/FFF1`, but ignore the v90 `7E FF ... EF` packet
family. Those guessed writes are removed. BLEDIM normal Power/Color/Brightness
and automated fades are intentionally disabled until the exact FFF1 application
payload is captured.

A new per-device **BLEDIM FFF1 Protocol Lab** records advertisement metadata,
reads standard Device Information/Battery values, logs FFF1 notifications, and
can replay an exact captured hex frame only to FFF1. It never writes the TI OAD
`F000FFC0/FFC1/FFC2` firmware-update service.

Shutdown behavior is also corrected for the physical wiring. Door is engine-fed
and loses power immediately at engine OFF, so the app records Door runtime 0
without trying to fade it. Dashboard + Center Console are headlight-fed and the
shutdown latch stays armed until the next engine start, allowing verified
headlight controllers to be faded/held at 0 during the post-lock 1–2 minute
courtesy-headlight interval. Until BLEDIM FFF1 is decoded, this suppression is
fully available for Lotus but not yet for the BLEDIM Dashboard light.


## v90.5.1 — iOS 26 TestFlight compile fix

The v90.5 TestFlight archive reached Swift compilation but failed in
`AmbientLightingView.swift` because the `bledimUndecoded` UI guard was declared
inside the LIGHT CONTROL section and then referenced again from the sibling
STARTUP ANIMATION section. v90.5.1 moves that guard to the common paired-device
scope. No BLE protocol, vehicle-state, or shutdown behavior changes from v90.5.
A source regression test now requires the guard to remain in the shared scope.

## v90.5.2 — iOS CI stale shutdown-test fix

The iOS 26 application build passed, but one older v90 source-inspection unit test
still expected the pre-v90.5 shutdown implementation. The test now matches the
corrected Door-power-loss/headlight-courtesy shutdown behavior. No runtime code
changed from v90.5.1.

## v90.7 — BLEDIM2 official iOS protocol recovered

An Apple Bluetooth diagnostic/sysdiagnose PacketLogger capture of the official BLEDIM2 iOS app resolved the previously unknown FFF1 command protocol. BLEDIM2 uses `55 AA` framed writes with an incrementing sequence byte, big-endian payload length, and an additive modulo-256 checksum. Captured commands are `0x80` power, `0x82` RGB, and `0x88` brightness. Normal BLEDIM controls and vehicle automation are re-enabled; the disproved v90 `7E FF ... EF` guesses remain retired. See `docs/V90_7_BLEDIM2_OFFICIAL_IOS_PROTOCOL.md`.


## v90.8 — simplified ambient state machine, smooth breath, presets, shortcuts

v90.8 supersedes the earlier startup/headlight-join/shutdown choreography. Field
observation established that all three ambient-light controllers can remain powered
after engine shutdown, so engine OFF no longer sends any automatic ambient-light
brightness or power command. The vehicle-state machine is intentionally limited to
one responsibility: while the engine-power session is ON, Dashboard or Center
Console headlight presence selects the Door's night target; absence of both selects
the Door's day target. A short internal post-engine settle still rejects the
pre-engine courtesy-headlight state.

Ambient animation/control is now independent of that vehicle state machine:

- one optional per-light **Animation on power-up** toggle (fresh BLE/power session or manual OFF -> ON);
- one global **Breath** animation only: current -> 0% -> 100% -> current;
- user-selectable 2x, 3x, 4x, or 5x repeats;
- user-selectable 1-15 second total breath duration;
- enabled lights discovered together are coalesced onto one shared animation clock,
  and late GATT-ready lights join the current breath phase;
- every manual device/group brightness change and every automatic Door day/night
  change uses a shared 1-15 second smooth transition instead of a target jump;
- animation/transition frames run on a 20 Hz scheduler and suppress duplicate rounded
  brightness writes.

Each individual light and each group now has five persistent color preset blocks.
Tap a block to apply it; long-press a block to replace that slot with the current
color-picker value. Device presets and group presets are independent.

The Ambient Lighting page no longer exposes the general Nearby BLE Devices list.
CoreBluetooth scanning, remembered UUID reconnect, OBD witness detection, and all
paired-light behavior remain active in the background.

A persistent three-button quick-action strip appears at the top of every main app
surface except My Trips/Logs:

- **Navigation** selects Navigation, arms HUD navigation, and presents the full-display
  capture picker in the normal iOS 27 build;
- **Music** selects Media and performs a one-tap Spotify recovery, authorizing only if
  needed or otherwise waking Spotify/resuming App Remote without clearing Keychain;
- **Ambient** selects Vehicle and deep-links directly to Ambient Lighting -> Paired
  Lights.

The BLEDIM2 protocol remains the official iOS-capture `55 AA` FFF1 implementation.
The 2026-08-24 PacketLogger capture was made with the **Dashboard** BLEDIM controller,
not Door; later field testing confirmed the same protocol works on both controllers.


## v90.8.1 — Breath duration clarification

- Breath always uses each light's actual runtime brightness at animation start; 50% was only an example.
- One repetition is `initial/current → 0% → 100% → initial/current`.
- If a manual or active Door day/night target changes while the breath is running, earlier repetitions still return to the original starting brightness and the final repetition returns smoothly to the latest target.
- `Breath duration / cycle` is 1–15 seconds **per repetition**. Therefore 3× at 9 seconds takes 27 seconds total.

## v90.8.2 — iOS CI breath regression fix

- Runtime behavior is unchanged from v90.8.1.
- Fixes a stale Swift source-regression assertion that still expected the pre-v90.8.1 fixed return leg (`100% -> initial`) on every breath cycle.
- CI now validates the intended v90.8.1 behavior: earlier cycles return to the captured initial brightness, while only the last return leg may end at a target changed during the running breath.
- CI also verifies that the configured breath duration is per cycle and total duration is `per-cycle duration × cycle count`.

## v90.9 — BLEDIM animation pacing + reliable Breath + editable presets

Field logs from v90.8.2 showed that the animation problem was transport/timing related,
not a different brightness opcode. The official BLEDIM2 iOS PacketLogger capture sends
continuous brightness-slider updates at roughly 100 ms intervals (~10 Hz), whereas
v90.8.2 drove both BLEDIM controllers at 20 Hz. During synchronized Breath this was
combined with one interleaved sequence counter for both BLEDIM peripherals, repeated
GATT rediscovery/read traffic, and synchronous per-frame logging on the MainActor.
The field log also showed real BLE timeout disconnects and an important re-entry bug:
a second Preview/power-up request could recapture a 1–5% in-progress animation frame
as the new return brightness, causing the Breath to finish nearly dark.

v90.9 therefore:

- keeps one shared wall-clock animation phase, but paces BLEDIM brightness writes at
  <=10 Hz and Lotus Lantern at <=20 Hz;
- uses a separate BLEDIM sequence counter for each physical controller;
- checks CoreBluetooth `canSendWriteWithoutResponse` and drops stale intermediate
  frames under backpressure instead of building a write queue;
- calculates progress from elapsed wall-clock time, so scheduler/BLE delays skip stale
  frames rather than extending a requested animation indefinitely;
- suppresses intermediate animation packet logging and rate-limits repetitive BLEDIM
  all-`FF` notification logs;
- stops rediscovering services on every watchdog pass once a control characteristic is
  already ready;
- ignores a repeated Preview/ON request for a light already participating in the active
  Breath, preserving its original start/return brightness;
- restores the saved steady-state target after a reconnect instead of an interrupted
  animation frame;
- keeps the common synchronized phase so Door, Dashboard, and Center remain visually
  aligned as closely as their different BLE transports allow.

The five device presets and five group presets are now visibly editable. Pick any color
with the normal picker, then tap the pencil under a preset slot to overwrite that slot.
Tap the color block itself later to apply it. Long-press replacement remains available
as a secondary interaction.

## v90.10 — physical headlight epochs + reliable ambient command delivery

Field logs from v90.9 showed that the remaining failures were primarily state-machine
and CoreBluetooth delivery problems rather than an incorrect BLEDIM2 command format.
Semantic writes such as Power ON, RGB restore, and final brightness could be skipped
when `writeWithoutResponse` backpressure was active, while the animation state machine
continued as if they had succeeded. The known vehicle lights were also being
cancelled/reconnected by the old six-second watchdog, and Dashboard/Center Breath
re-arming still depended on the older 15-second disconnect heuristic.

v90.10 changes the ambient runtime around the actual vehicle power behavior:

- Dashboard + Center Console use a **physical headlight-power epoch**. A new physical
  OFF -> ON event can start a fresh Breath immediately, even if the previous OFF interval
  was only a few seconds.
- A short dual-controller OFF debounce cancels an in-progress headlight Breath and lets
  a rapid ON/OFF/ON sequence start cleanly without stale animation ownership.
- Door day/night automation is brightness-only. A headlight state change cancels the
  old Door transition and smoothly retargets from the Door's current runtime brightness;
  it no longer resends Power/RGB as part of every day/night transition.
- Power, RGB, Breath baseline, restore brightness, and final brightness are serialized
  through retry-aware `writeWithoutResponse` helpers instead of being silently dropped
  under CoreBluetooth backpressure.
- The three known vehicle ambient controllers are exempt from the old six-second
  cancel/reconnect watchdog loop; pending connections are allowed to complete naturally
  when physical power becomes available.
- BLEDIM animation brightness uses the decoded protocol's native 0...255 resolution on
  the shared 20 Hz wall-clock phase. Logical 0% is a brightness command and is never
  converted into a BLEDIM Power OFF command.
- Breath uses a linear slider-like ramp while preserving the per-cycle duration model
  introduced in v90.8.1.
- Opening an individual or group control page initializes its color picker silently;
  simply visiting the page no longer emits an RGB command. Preset taps also issue only
  one RGB command.

The v90.9 source-regression tests were updated to validate these v90.10 invariants.

## v90.11 — authoritative headlight edges + automatic Spotify wake + selectable speed-limit sources

Field testing of v90.10 showed one remaining rapid-headlight race: Center/HUD auto-brightness
could already report OFF while Dashboard BLE was still connected or finishing a Breath. Door
therefore waited for the slower Dashboard disconnect before beginning its day transition, and a
stale Dashboard animation final could survive across a short OFF -> ON cycle.

v90.11 makes the same Center/ELK-BLEDOM presence edge that drives the HUD's native auto-brightness
the authoritative vehicle headlight state:

- HUD auto-brightness ON and Door night transition now start from the same event.
- HUD auto-brightness OFF and Door day transition now start from the same event; there is no wait
  for Dashboard's later CoreBluetooth timeout.
- Every headlight ON creates a fresh epoch. A physical OFF immediately invalidates Dashboard/Center
  Breath preparation, active frames, and final writes from the old epoch.
- A short OFF -> ON starts a clean new bootstrap even if a controller never fully left CoreBluetooth's
  connected state.
- Door transitions remain interruptible and always retarget from the latest successfully applied
  runtime brightness.

Spotify recovery is also changed from repeated blind `connect()` attempts to automatic wake:

- the saved App Remote token remains in Keychain;
- after two failed silent connection attempts, HUD Controller automatically invokes Spotify's wake
  path without clearing authorization;
- when iOS returns to HUD Controller (or the authorization callback arrives), a fresh App Remote
  reconnects automatically;
- the destructive Reset/Reauthorize action remains troubleshooting-only.

For speed-limit testing, the Vehicle page now exposes three independently selectable sources:

1. **Current** — unchanged decompiled HUDWAY/OSM matcher.
2. **Enhanced OSM** — separate directional/continuity-aware OSM matcher for A/B testing.
3. **HERE** — rolling GPS-trace route matching requesting `APPLICABLE_SPEED_LIMIT`; requires a HERE
   API key entered in the app and stored only in iPhone Keychain.

Switching sources clears the previous speed-limit sign until the selected source produces a fresh
result. The ambient red overspeed warning remains intentionally unimplemented because the iOS app
still does not receive the HUD/OBD vehicle-speed value directly; GPS speed is not used for that
proposed warning.

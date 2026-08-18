# HUD Cross-Platform Controller

A GitHub-first development repository for understanding and testing the HUD Drive hardware BLE protocol before implementing production Android and iOS clients.

## Repository layout

- `windows/` — working Python/Tkinter BLE protocol tester
- `tests/` — protocol encoder regression tests
- `android/` — reserved Android application directory
- `ios/` — reserved Expo/EAS iOS application directory
- `docs/` — protocol test plans and findings
- `.github/workflows/` — Windows, Android, and iOS build workflows

## Current milestone: Windows protocol validation

The Windows tester supports BLE scanning, connecting, RX notifications, raw TX/RX logs, initialization, navigation mode, maneuvers, auto/manual brightness, full screen, keep alive, and arbitrary raw hex packets.

### Build in GitHub Actions

1. Create a new GitHub repository.
2. Upload or push all files from this project.
3. Open the repository's **Actions** tab.
4. Select **Build Windows BLE Tester**.
5. Click **Run workflow**.
6. After the workflow succeeds, open its run and download the `HUD-BLE-Tester-Windows` artifact.
7. Extract and run `HUD_BLE_Tester.exe` on a Windows computer with Bluetooth LE.

GitHub Actions artifacts preserve build outputs after the job completes. The workflow uses a Windows runner, installs the pinned Python dependencies, runs protocol tests, builds the GUI with PyInstaller, and uploads both the `.exe` and a ZIP. 

### Build locally on Windows

```powershell
cd windows
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
python -m pytest ..\tests -q
pyinstaller --clean --noconfirm HUD_BLE_Tester.spec
```

Output:

```text
windows/dist/HUD_BLE_Tester.exe
```

## Future Android workflow

`.github/workflows/android-build.yml` is already included. It remains inactive until an Android Gradle wrapper exists under `android/`. When the Android project is added, pushes touching `android/**` will build and upload a debug APK.

## Future iOS workflow

`.github/workflows/ios-build.yml` is included for an Expo/EAS project. It remains inactive until `ios/package.json` and `ios/eas.json` exist. Add an Expo access token as the GitHub Actions secret `EXPO_TOKEN` before running iOS cloud builds.

## Safety

Test while parked. Do not interact with this software while driving. Keep the original HUD application disconnected during protocol tests because the HUD may accept only one BLE central connection.

## Windows BLE scan diagnostics

The Windows build now publishes two executables:

- `HUD_BLE_Tester.exe` — normal GUI build.
- `HUD_BLE_Tester_Diagnostic.exe` — same GUI plus a console window for WinRT/Bleak diagnostics.

When **Scan** is clicked, the GUI log must immediately show `SCAN BUTTON: clicked`, then `Starting BLE scan...`, then discovery events. The dropdown is intentionally **not HUD-only**; it displays every BLE advertiser returned by Windows. Nordic UART Service advertisers are marked with a star when that UUID is present in the advertising packet.

If Windows Settings can discover devices but the normal tester returns zero devices or reports a WinRT error, run the Diagnostic build and capture both the GUI log and console text.


## Windows PyWinRT packaging note

The Windows executable explicitly installs and bundles the PyWinRT projection
packages required by Bleak. In particular, `winrt-Windows.Foundation.Collections`
provides `winrt.windows.foundation.collections`, which is imported dynamically by
Bleak when advertisement packets are received. Both PyInstaller spec files carry
explicit hidden imports, and GitHub Actions verifies these imports before building.

## v4 workflow correction

The Windows workflow now runs `py_compile` before tests/PyInstaller. This catches
syntax/import-order problems immediately. `from __future__ import annotations`
is kept as the first executable statement in `windows/app.py`.

## v5 HUD connection watchdog fix

The original Android app does not treat the Nordic-UART GATT connection alone as
a fully alive HUD session. Immediately after connection it sends
`UartConnectionCheckCommandPacket` (`02 7D 7F 06 00 03`). The HUD responds with
`UartConnectionEventPacket` (`03/01/01` after unescaping). Every such event causes
the Android app to send a KeepAlive and reset its 20-second watchdog.

The Windows tester now mirrors that behavior automatically and logs unexpected
GATT disconnects explicitly.

## v6 serialized BLE TX

The original `HudNetworkManager` serializes all outgoing data: one packet is
active at a time and its 19-byte chunks are advanced only after the Android GATT
write callback. v6 mirrors that requirement with one async TX lock. Automatic
keep-alives are queued behind an in-progress maneuver instead of being allowed
to interleave with its chunks.

For protocol discovery, v6 also adds conservative no-response write pacing and
numbers every transaction (`TX#1`, `TX#2`, ...), making interleaving visible in
logs.

## v7 Navigation simulator and HUD UI controls

New test functions:

- **START 5-Leg Navigation Simulator**: enables navigation and runs five
  hard-coded maneuver legs. Distance is updated once per second, and the
  maneuver/street text changes between legs.
- **Time + Weather ON/OFF**: sends the real `DisplayTimeCommandPacket`
  (`2/9/4`, boolean payload). Despite the packet class name, the Android
  proxy method is named `showHideTimeWeatherPanel`, indicating this is the
  bottom time/weather panel control.
- **Dashboard presets**: sends `HudWidgetCommandPacket` (`2/111/0`) with the
  same widget names used by the Android application, including `Empty`,
  `Simple`, `Navigation`, `Speedo`, `Weather`, and `Time`.
- **Custom UI Sequence**: a timed sequence of dashboard commands for visual
  experimentation. This does **not** claim to alter the HUD firmware's true
  power-on/boot animation; no dedicated boot-animation packet was found in
  the decompiled Android client.


## iOS v0.1

A native SwiftUI iPhone client is now under `ios/`.

Highlights:
- validated HUD BLE protocol and connection watchdog;
- serialized 19-byte transport;
- manual and simulated navigation pipeline;
- HUD-style dashboard controls;
- persistent shareable logs;
- Shortcuts/App Intents scaffold;
- GitHub Actions for simulator CI, signed Ad Hoc IPA, and TestFlight.

See `docs/IOS_APPLE_DEVELOPER_SETUP.md`.

## v11 iOS CI test-host correction

The visible app label remains `HUD Controller` through `CFBundleDisplayName`,
but the executable product now keeps the target name `HUDController`. This
matches XcodeGen's generated unit-test host path and avoids the prior
`Could not find test host` error.


## v12 — iPhone notifications / ANCS configuration

The iOS client now implements the HUD firmware's notification configuration
packets discovered in the decompiled client: global enable, filter
initialization, per-app filters, notification timeout, and message-line count.

A Maps experiment section enables Google Maps, Apple Maps, and Waze filters for
hardware testing. Classic ANCS remains accessory-facing: HUD Drive receives
the notification content directly from iOS.


## v13 — TestFlight signing identity correction

The signed archive workflows now explicitly use `Apple Distribution` as the
code-signing identity. A pre-archive diagnostic step lists available signing
identities and verifies the provisioning profile's name, Team ID, and
application identifier before Xcode archives the app.


## v14 — App Store Connect validation correction

The TestFlight archive/export had already succeeded, but App Store Connect
rejected the IPA for three metadata/build-environment reasons. v14:

- moves iOS GitHub jobs to `macos-26`;
- explicitly selects Xcode 26.6 and verifies the iPhoneOS SDK is 26+;
- marks HUD Controller as iPhone-only (`TARGETED_DEVICE_FAMILY = 1`);
- declares supported iPhone orientations;
- uses the modern `UILaunchScreen` Info.plist declaration.

This avoids the previous iPad multitasking validation path and satisfies
Apple's current SDK minimum for App Store Connect uploads.


## v15 — iOS HUD discovery correction

The iPhone scanner no longer requires the HUD Nordic UART Service UUID to
appear in the BLE advertisement. Physical Windows testing showed HUD Drive
can advertise only its local name and expose NUS after GATT connection.

iOS now:
- scans all BLE advertisements;
- logs every discovery including advertised service UUIDs;
- shows named peripherals in the picker;
- sorts HUD-named devices first;
- automatically selects the first HUD device;
- verifies the NUS service only after connecting.


## v16 — CI simulator + TestFlight build-number fixes

- iOS CI no longer hard-codes an iPhone model. It selects an available iPhone
  simulator from `simctl` and builds/tests using that simulator's UDID.
- TestFlight now writes GitHub's unique `GITHUB_RUN_NUMBER` directly into the
  generated app `Info.plist` as `CFBundleVersion` after XcodeGen runs.
- The workflow verifies the archived `.app` has that exact build number before
  exporting/uploading the IPA.


## v17 — ANCS connection mode + remembered HUD auto-connect

Physical iPhone testing showed all proprietary notification-filter packets were
sent successfully, but the BLE connection itself had never been established
with CoreBluetooth's ANCS requirement.

v17 connects with:

- `CBConnectPeripheralOptionRequiresANCS = true`
- `CBConnectPeripheralOptionEnableAutoReconnect = true`

After the first successful HUD connection, the app saves the CoreBluetooth
peripheral UUID in `UserDefaults`. On future launches it calls
`retrievePeripherals(withIdentifiers:)` and connects automatically without a
manual scan when iOS can retrieve the same HUD.

A "Forget" button clears the remembered HUD.


## v18 — restore normal BLE connection; observe ANCS authorization

Physical testing showed `CBConnectPeripheralOptionRequiresANCS = true` caused
the HUD connection to remain pending indefinitely before ANCS authorization was
established. v18 removes ANCS as a hard connection requirement.

The app retains:
- saved HUD peripheral UUID;
- launch-time `retrievePeripherals(withIdentifiers:)`;
- `CBConnectPeripheralOptionEnableAutoReconnect = true`.

It adds:
- `CBPeripheral.ancsAuthorized` logging before/after connection;
- `centralManager(_:didUpdateANCSAuthorizationFor:)` logging;
- `didFailToConnect` diagnostics;
- an "ANCS authorized" field in Diagnostics.

This separates ordinary HUD transport from ANCS authorization instead of making
ANCS a prerequisite for the transport itself.


## v19 — restore known-good connection; retain app-level auto-connect

Physical iPhone logs from v18 showed CoreBluetooth rejecting the connection
request immediately with `One or more parameters were invalid`. The HUD itself
was advertising normally at approximately -53 dBm.

v19 therefore restores the exact connection form that already worked on the
physical iPhone:

`central.connect(peripheral, options: nil)`

Remembered-device behavior remains implemented independently:

1. after the first successful connection, save `CBPeripheral.identifier`;
2. on later app launches call `retrievePeripherals(withIdentifiers:)`;
3. if iOS returns the HUD, call the same known-good `connect(..., options: nil)`;
4. otherwise fall back to scanning.

This provides launch-time auto-connect without depending on CoreBluetooth's
system auto-reconnect connection option.

ANCS authorization observation remains enabled (`CBPeripheral.ancsAuthorized`
and `didUpdateANCSAuthorizationFor`), but ANCS is not made a prerequisite for
the normal HUD transport.


## v20 — branding cleanup and source separation

Physical iPhone testing verified that normal notification events such as
Messages and KakaoTalk reach the HUD. Spotify current-track metadata and map
turn guidance do not arrive through the notification pipeline.

The UI now separates:
- accessory notifications;
- future media / Now Playing source;
- future navigation providers.

Project-owned branding has also been changed from the prior vendor name to
`HUD` / `Hud` throughout code, documentation, workflow labels, project target
names, and generated artifact names. The physical device may still advertise
its manufacturer-defined Bluetooth name at runtime.


## v21 — Spotify-only experiment

v21 deliberately does **not** add an in-app route engine.

Navigation remains external-app-only. Apple Maps, Google Maps, Waze, or another
separate map application must remain the route source; future navigation work
will focus only on extracting turn guidance from those external apps.

The only major new provider in v21 is Spotify:
- Spotify iOS App Remote integration;
- player-state subscription;
- current track/artist display;
- local notification bridge to the already-validated HUD notification path;
- manual Media Test Notification for isolated testing.

See `docs/V21_SPOTIFY_SETUP.md`.


## v22 — Spotify Observation compile fix

Xcode 26 rejected the Spotify controller because the `@Observable` macro tried
to synthesize observation storage for the lazy Spotify SDK internals. Those
objects are not UI state and should not be observed.

`SPTConfiguration` and `SPTAppRemote` are now marked with
`@ObservationIgnored`, preserving them as normal lazy stored properties while
the user-visible status/track/artist properties remain observable.


## v23 — unexpected-disconnect reconnect watchdog

v23 adds an app-level reconnect watchdog while preserving the physical-device
connection path that has already proven stable:

`central.connect(peripheral, options: nil)`

Behavior:

- the first successful HUD connection remains persisted by CoreBluetooth UUID;
- if the link drops unexpectedly, the app schedules reconnect attempts;
- retry backoff is 1s → 2s → 4s → 8s → 15s → 30s, then every 30s;
- successful GATT/transport connection resets the backoff;
- reopening the app still retrieves and auto-connects the saved HUD;
- pressing Disconnect explicitly pauses automatic reconnect;
- pressing Scan, Connect, or Reconnect re-enables automatic reconnect;
- Forget clears the saved HUD and disables retries.

The reconnect loop does not use CoreBluetooth's
`CBConnectPeripheralOptionEnableAutoReconnect`, since physical testing showed
that option was rejected for this accessory.


## v24 — vehicle integration

This combined physical-test build adds:

- original-style HUD-managed OBD-II connect/disconnect and OBD event parsing;
- configurable left/right OBD item packets;
- original-style GPS speed + OpenStreetMap Overpass speed-limit engine;
- native HUD speed and speed-limit packets;
- app-level `BLEDOM` BLE presence monitor driving HUD auto brightness;
- Spotify metadata sent through the firmware-native MusicNotificationPacket;
- all v23 HUD reconnect-watchdog behavior retained.

See `docs/V24_VEHICLE_INTEGRATION.md` for the test sequence and known
assumptions.


## v25 — RX frame-range compile fix

The first v24 iOS CI run exposed a Swift `Data.subdata(in:)` range-type error
in the new BLE RX frame reassembly helper. `subdata(in:)` accepts a half-open
`Range<Data.Index>`, not a `ClosedRange`.

Frame extraction now computes the index immediately after ETX and uses:

`buffer.startIndex..<endExclusive`

for both `subdata(in:)` and `removeSubrange(_:)`.

A protocol test was added for complete, fragmented, and back-to-back RX frames.
All v24 vehicle-integration functionality is otherwise unchanged.


## v26 — BLEDOM CoreBluetooth startup-crash fix

The v25 app compiled, but the simulator test host aborted before XCTest could
start. `AmbientLightMonitor` created a `CBCentralManager` using
`CBCentralManagerOptionRestoreIdentifierKey` without implementing
`centralManager(_:willRestoreState:)`.

CoreBluetooth asserts in that configuration.

v26 removes the restoration identifier from the independent BLEDOM presence
scanner and creates that central manager with `options: nil`. The monitor still
supports app-level BLE scanning for `BLEDOM`; only CoreBluetooth state
restoration for that secondary scanner is removed.

All v24/v25 vehicle features remain unchanged.


## v27 — mph conversion

All app-side vehicle speed and posted speed-limit behavior now uses **mph**.

- GPS speed is converted from m/s to mph.
- OSM `maxspeed="35 mph"` remains 35.
- Bare OSM numeric speed limits are interpreted as km/h and converted to mph.
- Speed-limit tolerance/warning values are mph.
- HUD current-speed and speed-limit packets are sent mph values.
- Vehicle UI and logs consistently show mph.

The HUD-managed OBD packet protocol itself is unchanged.


## v28 — mph + Spotify automatic reconnect

v28 keeps all v27 mph behavior and adds Spotify App Remote persistence:

- first authorization remains user-driven;
- the App Remote access token is stored in iOS Keychain;
- subsequent app launches restore the saved token;
- HUD Controller automatically calls `appRemote.connect()` when the app becomes active;
- app backgrounding disconnects App Remote, following Spotify's lifecycle guidance;
- returning active automatically reconnects;
- transient Spotify disconnects retry after three seconds;
- if authorization is no longer accepted, use the Media tab to authorize again.

Spotify generally needs to be actively playing for App Remote to connect while
Spotify itself is backgrounded.


## v29 — mph tuple compile fix

The first v28 CI run exposed one stale field name left behind by the mph
conversion. `parseMaxSpeed` now returns `(mph, sourceWasMph)`, while
`makeSegment` still referenced the former `isMph` tuple member.

v29 updates that reference to `parsed.sourceWasMph`.

No runtime behavior changes were made; all v28 features remain intact.


## v30 — iOS 27 capture + reliability

- fixes Spotify manual re-authorization getting trapped on a stale saved token;
- adds richer Spotify App Remote error logging;
- BLEDOM timeout now supports 1–30 seconds and uses CoreBluetooth state restoration;
- exposes experimental HUD auto-brightness/light raw event value;
- OBD UI now has persistent Freeride + Navigation left/right widget profiles;
- fixes OBD UI "searching" state being overwritten after already connected;
- adds iOS 27 ScreenCaptureKit full-display capture at ~1 Hz;
- adds Vision OCR + Google Maps maneuver parser;
- adds Photos screenshot OCR mode for testing away from the car;
- persists user-configurable settings immediately.

See `docs/V30_IOS27_CAPTURE_AND_RELIABILITY.md`.


## v31 — Xcode 27 GitHub Actions runner

The first v30 CI attempt ran on the ordinary `macos-26` image and explicitly
selected Xcode 26.6. That toolchain ships an iOS 26.x SDK, so the new iOS 27
`ScreenCaptureKit` module could not be imported.

v31 changes both iOS CI and TestFlight workflows to GitHub's dedicated:

`runs-on: xcode-27`

preview image.

The workflows now verify that the selected iPhoneOS and simulator SDK major
version is at least 27 before generating/building the project. CI also checks
that `ScreenCaptureKit.framework` exists in the selected simulator SDK.

No application behavior from v30 was removed.


## v32 — restore full iOS CI/TestFlight workflows

v31 accidentally truncated both workflow files after the Xcode 27 verification
step. A green workflow therefore meant only that checkout and SDK verification
succeeded; no project generation, build, archive, IPA export, or TestFlight
upload occurred.

v32 restores the complete v30 CI/TestFlight pipelines and changes only the
runner/toolchain portions to `xcode-27`.

The TestFlight workflow now explicitly:
1. verifies Xcode/iOS 27;
2. installs XcodeGen/Fastlane;
3. generates the project and injects build number + Spotify client ID;
4. installs signing certificate and provisioning profile;
5. archives the app;
6. verifies `CFBundleVersion == GITHUB_RUN_NUMBER`;
7. exports an App Store IPA;
8. verifies the IPA physically exists;
9. uploads it with `fastlane pilot`;
10. uploads the IPA as a GitHub Actions artifact.

A successful v32 TestFlight job therefore means an actual upload command ran.


## v33 — ScreenCaptureKit physical-device build guard

The v32 CI log confirmed Xcode 27 beta 4 and both iPhoneOS/iPhoneSimulator
27.0 SDKs were selected. The physical iPhoneOS SDK contains
`ScreenCaptureKit.framework`, but the simulator Swift build cannot resolve the
`ScreenCaptureKit` module.

Apple's iOS 27 ScreenCaptureKit sample is documented as requiring a physical
device. v33 therefore:

- compiles the real ScreenCaptureKit implementation only when
  `canImport(ScreenCaptureKit) && !targetEnvironment(simulator)`;
- keeps a simulator fallback with identical observable state;
- preserves the saved-photo Vision OCR test on Simulator;
- weak-links ScreenCaptureKit for physical device builds;
- keeps TestFlight/device builds on Xcode 27 so the real implementation is
  included;
- changes CI validation to require the framework only in the iPhoneOS device SDK.

No navigation/OCR, BLE, OBD, Spotify, persistence, or BLEDOM behavior was removed.


## v34 — persistent settings initializer compile fix

v33 successfully moved past the ScreenCaptureKit simulator problem. CI then
exposed a Swift initialization rule in the new persistent `HudSettings` model.

The nested `bool` and `integer` helpers referenced the instance property
`defaults`, which implicitly used `self` before all stored properties had been
initialized.

v34 uses a local `let store = UserDefaults.standard` throughout initialization,
then assigns every persisted setting from that local reference. Runtime
persistence behavior is unchanged.


## v35 — remove global ScreenCaptureKit linker flag

v34 compiled successfully under the iOS 27 simulator SDK, proving that the
conditional Swift implementation works. The remaining CI failure was at link
time:

`ld: framework 'ScreenCaptureKit' not found`

The cause was a global:

`-weak_framework ScreenCaptureKit`

setting in `project.yml`. That flag forces the simulator linker to resolve a
framework that does not exist in the simulator SDK.

v35 removes the global linker flag entirely. The real device-only
ScreenCaptureKit source still imports the framework under:

`#if canImport(ScreenCaptureKit) && !targetEnvironment(simulator)`

so physical iOS 27 builds use it normally, while simulator builds compile and
link only the fallback implementation.


## v36 — update obsolete ambient restoration unit test

v35's application target compiled and linked successfully. The only CI failure
was an old source-inspection test that asserted the ambient BLE monitor must not
use `CBCentralManagerOptionRestoreIdentifierKey`.

That assertion became obsolete when v30 intentionally added CoreBluetooth state
restoration *and* implemented `centralManager(_:willRestoreState:)` for better
background/locked-screen behavior.

v36 updates the regression test to verify the correct invariant instead:
restoration identifier and restoration callback must either both exist or both
be absent. For the current design, both are explicitly required.


## v37 — use the actual iOS 27 ScreenCaptureKit API surface

The v36 TestFlight archive successfully imported ScreenCaptureKit from the
iPhoneOS 27 SDK. It then exposed six configuration properties that Xcode marks
unavailable on iOS:

- `allowedPickerModes`
- `allowsChangingSelectedContent`
- `excludedBundleIDs`
- `minimumFrameInterval`
- `queueDepth`
- `scalesToFit`

Those properties are part of ScreenCaptureKit's broader/macOS API surface but
are not usable by an iOS 27 app.

v37 follows Apple's iOS sample pattern instead:

- configure the shared picker only with iOS-supported picker controls;
- call `picker.present()` for full-display selection;
- create a default `SCStreamConfiguration`;
- disable audio;
- attach the `.screen` stream output;
- throttle Vision OCR in application code to approximately 1 Hz.

The existing `process(pixelBuffer:)` 0.8-second guard remains the effective
frame-processing throttle, so removing `minimumFrameInterval` does not cause
OCR to run at display frame rate.


## v38 — original dashboard widgets + capture recovery experiment

### Correct Freeride/Navigation widget protocol

Reverse engineering of the original Android dashboard editor shows that visible
side widgets are selected with `HudWidgetCommandPacket`, not
`OBDIICustomItemInternalPacket`.

Exact packet:
- command = 2
- param1 = 111
- param2 = 0
- payload = writeUTF(left), writeUTF(center), writeUTF(right), int32 type
- type 0 = Freeride
- type 1 = Navigation

v38 uses the original SideWidget dash names:
Speedo, MaxSpeedo, AvgSpeedo, Weather, Time, TraveledDistance, Cost, TripTime,
ETA, None, RPM, Battery, Gasoline, GasolineConsumption, EngineCoolantTemp,
EngineOilTemp.

Trip Time is therefore now a genuine original-protocol option.

### Screen-lock experiment

iOS 27 stopped the full-display stream during physical lock in the prior test.
v38 cannot override the OS lock-screen rendering policy, but adds:
- optional idle-timer suppression so the phone does not auto-lock;
- cached `SCContentFilter`;
- automatic restart attempt after unexpected stream termination;
- another cached-filter restart attempt when the app becomes active after unlock;
- explicit recovery-success/failure logging.

This lets the next device test determine whether the filter remains reusable
across lock/unlock without showing the system picker again.

### OCR stability

A new maneuver/street must appear in two consecutive OCR frames before being
sent to the HUD. Identical maneuvers are suppressed unless distance changes by
at least 10 meters.

### Spotify

The decompiled original application's default music notification filter uses
`com.kivic.music` (icon 3), not Spotify's Android/iOS package identifier.
v38 enables that firmware-native filter and sends MusicNotificationPacket using
`com.kivic.music`.


## v39 — validated auto-navigation + experimental Spotify widget probe

### Screen capture / lock behavior

Physical testing showed that iOS 27 terminates the full-display ScreenCaptureKit
stream when the device is manually locked. The framework reports the stop as
`SCStreamError.userStopped`, and restarting the cached filter while locked fails.

v39 therefore:
- retains `screen-capture` background mode for normal app backgrounding;
- keeps the optional idle-timer lock prevention;
- retains recovery attempts after interruptions/unlock;
- logs the exact ScreenCaptureKit NSError domain/code on stop;
- does not claim that capture can continue behind the iOS lock screen.

### Validated automatic navigation

v38 proved that loose OCR validation could misclassify HUD Controller UI text
("Keep screen awake during capture") as a navigation instruction.

v39 now requires:
- a navigation-like distance line;
- a nearby explicit maneuver phrase;
- confidence >= 80;
- two consecutive valid frames for a new maneuver/street.

After the first confirmed navigation result, the app automatically sends
Navigation ON and then continuously sends validated maneuver updates. Invalid
frames are skipped and do not clear the last valid HUD instruction.

### Spotify side-widget experiment

The original decompiled SideWidget enum has no Music/Now Playing widget.
v39 nevertheless adds `Spotify / Music (experimental)` using the test dash token
`Music`. When selected, Spotify metadata continues to be sent through the
firmware MusicNotificationPacket and the corresponding dashboard is re-applied.

This is explicitly a firmware probe, not a confirmed original widget.


## v40 — reserve the original Weather side widget for Music

The v39 physical test showed that the undocumented dashboard token `Music`
changes the HUD layout but renders a blank side area. The original decompiled
SideWidget enum does not contain a Music widget.

v40 removes that fake/undocumented token.

Instead:

- the iPhone UI no longer exposes a widget named Weather;
- that option is displayed as `Music`;
- selecting `Music` still sends the original, known-valid firmware dashName
  `Weather`;
- Spotify metadata continues through the corrected native music filter and
  `MusicNotificationPacket`;
- when Spotify metadata changes and a Music slot is selected, the appropriate
  Freeride/Navigation dashboard is re-applied.

This deliberately sacrifices the Weather side widget, which is acceptable for
the intended configuration, while keeping the HUD on a firmware-supported
dashboard layout.

Important: the original weather data packet contains numeric weather fields,
not arbitrary strings. Therefore v40 does not falsely encode artist/title as
weather data. The Weather-as-Music slot is the known-good visual container for
the next text-injection experiments.

All v39 validated automatic navigation behavior is retained.


## v41 — persistent text renderer probe

The v40 device test conclusively showed that selecting the real `Weather`
dashboard widget produces the normal weather icon and a 0-degree value. Spotify
artist/title data sent through `MusicNotificationPacket` does not populate that
widget.

v41 therefore stops treating Weather as Music and restores the original
firmware widget list.

A new Media → Persistent Text / Music Probe panel tests known text-bearing paths
independently with explicit strings:

- Phone-name command (`2 / 123 / 0`);
- native MusicNotificationPacket (`1 / 12 / 0`);
- arbitrary NotificationPacket categories with selectable package/title/message;
- notification category sweep 0–15;
- known persistent navigation maneuver text renderer (`2 / 100 / 1`);
- raw arbitrary UTF strings supplied as dashboard widget identifiers.

The probe can populate its title/message from the currently connected Spotify
track. Every test route is logged with its category, package identifier, title,
and message.

The purpose of this build is discovery: first identify which firmware renderer
can visibly display arbitrary text persistently; only then bind live Spotify
updates to that renderer.

All validated automatic ScreenCaptureKit navigation behavior from v39/v40 is
retained.


## v42 — AppState text-probe initialization fix

The first v41 CI run reached Swift compilation and failed only because the new
`HudTextRendererProbe` stored property had not been initialized before the
Spotify callback captured `self`.

v42 initializes:

`self.textProbe = HudTextRendererProbe(bluetooth: bluetooth, logger: logger)`

immediately after Spotify is constructed and before any callback captures
`AppState`.

No runtime probe behavior or other feature changed.


## v43 — remove obsolete Weather-as-Music regression tests

The v42 application target compiled, but CI failed while compiling unit tests.
Two older tests from the v39/v40 Weather-as-Music experiment still referenced
the removed `HudSideWidget.isMusicDisplaySlot` property and expected Weather's
UI label to be `Music`.

v43 updates those tests to the current architecture:

- Weather firmware token remains `Weather`;
- Weather UI label remains `Weather`;
- `isMusicDisplaySlot` is intentionally absent;
- the v41 Persistent Text / Music Probe tests remain active.

No runtime application behavior changed.


## v44 — HUD session rehydration + persistent speed-limit settings

The CarPlay drive log showed that a physical HUD power-cycle can reset firmware
state before iOS reports a CoreBluetooth disconnect. The HUD's firmware/version
event (`3 / 5 / 0`) reappeared after the power interruption, so v44 treats that
event as a HUD-session reset signal.

### Automatic HUD rehydration

On a fresh BLE transport or firmware-session reset, v44 re-applies persisted
state without stopping ScreenCaptureKit:

- system time / keepalive / phone name / full-screen mode;
- manual/automatic brightness;
- time/weather toggle;
- notification filters;
- Freeride and Navigation dashboard widgets;
- OBD auto-connect;
- ambient-light-derived auto-brightness state;
- GPS/OSM speed-limit state and warning tolerance;
- current validated screen-capture navigation state;
- current Spotify metadata packet/filter when available.

If screen capture is still running and has a previously validated maneuver, the
HUD is automatically put back into Navigation mode and the cached maneuver is
re-sent immediately.

### OBD robustness

OBD connection state is now considered HUD-session-local. It is cleared when:

- the HUD BLE transport disconnects;
- a HUD firmware-session reset is detected;
- the user explicitly requests OBD disconnect.

When OBD auto-connect is enabled, the app retries every five seconds until the
HUD's actual OBD event reports `connected=true`. A stale local `connected=true`
value can no longer block reconnection after a physical HUD reboot.

### Ambient BLE hysteresis

BLEDOM presence still enables HUD Auto Brightness immediately. Absence now
requires three complete timeout windows. A 2-second timeout therefore requires
about 6 seconds without a matching advertisement before Auto Brightness is
disabled. This is intended to prevent normal BLE advertising gaps from
flapping the HUD brightness mode.

### Persistent speed-limit settings

The following are now stored in UserDefaults and restored on app launch:

- original-style GPS/OSM speed engine enabled state;
- Show speed-limit sign;
- warning tolerance in mph.

Changing the warning tolerance forces the currently displayed speed-limit
threshold to refresh. Enabling the speed-limit sign also ensures the GPS/OSM
engine is running.

The diagnostic persistent-text/music probe fields are also persisted so test
configuration survives app relaunch.

### Apple Maps

No Apple Maps OCR assumptions are added in v44. The Google Maps parser remains
unchanged. A future Apple Maps screenshot can be added as a separate parser
layout/test fixture rather than weakening the validated Google Maps rules.


## v45 — automatic Google/Apple navigation + field reliability

This release combines the August 13 CarPlay field-test fixes into one
automation-focused build.

### Automatic navigation-source detection

There is no Google/Apple selector. OCR/layout evidence classifies each frame as
Google Maps, Apple Maps, or unknown.

Google indicators include `Directions`, `In <distance>`, and textual maneuver
phrases. Apple indicators include `End Route`, `Proceed to the route`, and
repeated standalone distance/road cards.

Apple Maps `Proceed to the route` is an active navigation state rather than an
OCR rejection.

### Navigation lifecycle

The capture controller now tracks:
- active route;
- approach/proceed-to-route;
- reroute;
- explicit Maps home/inactive view;
- inferred/explicit arrival;
- unknown/transient OCR.

A structurally strong reroute may immediately replace the previous maneuver
without requiring continuity with the old street or direction. Explicit Maps
home screens return the HUD to Freeride after two confirming frames. Unknown
screens require six consecutive frames before Navigation is turned off.

When the last maneuver was within 80 m and Maps returns to its home view, the
HUD displays the existing Destination maneuver for about five seconds before
Navigation OFF.

### Distance handling

The parser explicitly retains the original `ft`/`mi` OCR string in diagnostics
and always chooses the first/top current route card. Distances below one mile
remain converted from the original feet value directly to meters for the HUD
protocol rather than selecting a later mile-denominated route row.

### ScreenCaptureKit recovery

A stale-frame watchdog detects streams that exist but stop delivering frames.
Unexpected stops and start failures rebuild `SCStream` from the cached content
filter using exponential retry delays (1, 2, 4, 8, then 12 seconds).

A stopped capture immediately returns the physical HUD to Freeride rather than
leaving a stale maneuver frozen.

### BLEDOM background/locked-screen monitoring

After the first successful BLEDOM discovery, its CoreBluetooth UUID is saved.
The app then maintains a restoration-enabled BLE connection/pending connection
to that peripheral.

CoreBluetooth connection/disconnection callbacks are OS-delivered and are more
appropriate for background/locked-screen state than a Swift Task polling
duplicate advertisements. Peripheral disconnect turns HUD Auto Brightness OFF;
the app immediately leaves another connect request pending so BLEDOM power-on
can reconnect and turn it ON again.

Foreground advertisement scanning remains as discovery/fallback.

### OBD

Existing installs receive a one-time v45 migration that turns OBD auto-connect
ON, because earlier debugging often left the persisted switch OFF. After the
migration, a user may still intentionally disable it.

When enabled, HUD/OBD reset or disconnect keeps retrying every four seconds
until the HUD explicitly reports OBD connected.

### Rectangular speed-limit sign

`HudSpeedLimitAndToleranceCommandPacket` now sends its square/rectangular style
flag as `1` by default and the GPS/OSM engine explicitly requests that style.
The same native speed-limit state is independent of Freeride vs Navigation
layout.

### Apple Maps graphical maneuver arrows

Apple Maps route lists use graphical turn arrows rather than textual `Turn
right` phrases. v45 includes an initial local image-shape classifier for the
first route-card arrow (left/right/straight) while OCR supplies the distance
and road. This is intentionally logged/tested in the field and can be refined
from additional Apple Maps screenshots without adding a manual source switch.


## v46 — update stale v44 navigation rehydration test

The v45 CI run successfully built the application and all v45 navigation,
BLEDOM, OBD, and speed-limit regression tests passed.

The only failure was an older v44 source-inspection test that searched for an
exact log sentence removed by the v45 navigation lifecycle rewrite.

v46 updates that test to verify behavior rather than old wording:

- `hudSessionDidReset(reason:)` still exists;
- a physical HUD reset preserves ScreenCaptureKit;
- the HUD navigation state is re-armed;
- the latest validated maneuver is sent again;
- the HUD reset handler does not call `stop()` or reopen the system capture
  picker.

No runtime application behavior changed from v45.


## v47 — drive reliability + maximum automation

- Fixed a protocol-unit bug in GPS fallback speed. `CLLocation.speed` is now
  converted to km/h for the HUD's native SpeedNotification packet while the
  HUD remains configured to display mph. This fixes the characteristic
  ~0.62x low reading (for example 45 mph appearing near 28 mph).
- Rejects stale or very poor-accuracy GPS fixes.
- BLEDOM uses hybrid advertisement + persistent GATT recovery: OFF remains
  event-driven; after disconnect the app both scans and leaves a connection
  pending, and a matching advertisement turns Auto Brightness ON immediately.
- OBD auto-connect now has a continuous 10-second keep-connected health loop.
  The known HUD protocol reports connection/PID masks but does not stream raw
  PID values back to the phone, so v47 does not falsely claim to validate RPM
  or vehicle-speed freshness. Instead it periodically reasserts the
  idempotent HUD→OBD connect command and resumes the retry loop whenever local
  connection state is lost.
- HUD boot restoration is now three-phase: base session, persisted settings
  after firmware settles, then a delayed display-critical reassertion. This
  specifically reasserts time/weather OFF, dashboard widgets, brightness,
  navigation, and speed-limit state after firmware defaults have loaded.
- Circular speed-limit style was removed from the command API. Every
  speed-limit packet now hard-codes the rectangular style flag.
- Screen capture has a persisted `captureDesired` state. Unexpected stream
  termination preserves the current navigation maneuver while the app
  automatically rebuilds/retries capture. Only explicit Stop Capture disables
  that desire.
- When capture is desired but no in-memory content filter exists (for example
  after a fresh process launch), the app automatically presents Apple's system
  content-sharing picker once while foregrounded. The user still performs the
  required privacy-sensitive Entire Display selection.
- `screen-capture` remains enabled in UIBackgroundModes for iOS 27 full-display
  background capture.


## v48 — update stale speed-unit regression test

The v47 CI run built successfully and all six v47 drive-reliability tests
passed. The only failure was an older `SpeedUnitTests` assertion that rejected
any use of km/h in `OriginalSpeedLimitEngine`.

That assertion predates the v47 protocol correction.

The intended invariant is now tested explicitly:

- app/UI/current-speed state remains mph;
- `CLLocation.speed` is converted to mph for app state;
- immediately before `SpeedNotification`, the same m/s value is converted to
  km/h because that HUD protocol field is natively km/h;
- the mph number must never again be passed directly to the km/h packet field;
- HUD unit settings remain configured for mph display.

No runtime code changed from v47.


## v49 — remove invalid unit-settings test helper

The v48 application build succeeded. The test target failed to compile because
`V48SpeedProtocolBoundaryTests` referenced a helper named
`HudCommands.unitSettings(...)` that does not exist in this repository.

v49 removes that invented test dependency and verifies the actual code paths:

- 45 mph converts to approximately 72 km/h at the protocol boundary;
- `HudCommands.speedNotification(kmh:)` encodes the supplied km/h value;
- application-facing/current-speed state remains mph;
- the mph value is never passed directly into the HUD's km/h packet field.

No runtime application code changed from v48.


## v51 — correct SpeedNotification packet-shape regression test

The v49 app target built successfully and 66 of 67 tests passed. The sole
failure was the v48 speed protocol test, which incorrectly assumed
`speedNotification(kmh:)` used a `2 / 102 / 0` Int32 packet.

The actual repository implementation intentionally uses the generic
notification packet path:

- command = 1
- category/p1 = 14
- p2 = 0
- package name = empty
- title string = the km/h numeric value
- message = empty

v51 updates the regression test to verify that real packet shape and confirm
that the encoded payload contains the supplied km/h value.

No runtime application code changed from v49/v47.


## v51 field reliability update

- ScreenCaptureKit raw-frame heartbeat is independent of OCR; capture loss immediately returns the HUD to Freeride.
- Automatic capture recovery retries indefinitely and invalidates a cached filter after repeated start failures, then presents a Resume Capture path for a fresh Entire Display selection.
- Apple Maps destination-side arrival phrases, route-shield cleanup, decimal-distance candidate selection, lane-guidance parsing, and feet-boundary preservation were added.
- Ambient BLE absence-timeout Stepper no longer self-mutates from `didSet`.
- OBD reconnect uses a generation token to prevent overlapping retry loops.
- Native music/Spotify HUD popups now have a persisted enable/disable setting.
- Last known speed limit is persisted so rectangular style can be reasserted earlier after HUD reboot.


## v52 — update stale ambient-timeout regression test

The v51 iOS application target built successfully and 73 of 74 tests passed.
The only failing test was an older source-inspection assertion that looked for
the pre-v51 timeout implementation string `max(1, d.integer(forKey:`.

v51 intentionally replaced that implementation to fix the Stepper crash:
timeout clamping now goes through `clampedTimeout(_:)` and
`setAbsenceTimeout(_:)`, while the `didSet` observer only persists the already
clamped value.

v52 updates the regression test to verify the actual safety invariants:

- 1 second remains the minimum supported timeout;
- 30 seconds remains the maximum;
- restored UserDefaults values are clamped;
- UI changes use the safe setter;
- `absenceTimeoutSeconds.didSet` never recursively assigns
  `absenceTimeoutSeconds`.

No runtime application behavior changed from v51.


## v53 — automatic Spotify reconnect + remove text/music probe

Spotify App Remote is now designed as an authorize-once service.

- Saved App Remote authorization continues to load from Keychain.
- Normal connection/reconnection never clears the saved token.
- Unexpected disconnects retry after 2 s, 5 s, 10 s, then every 15 s.
- Foreground/app-active transitions immediately resume automatic connection.
- The normal Media UI no longer presents a Connect/Re-authorize button on every
  drive.
- `Authorize Spotify` appears only when no saved authorization is available.
- Explicit `Re-authorize Spotify` remains under the troubleshooting menu and is
  the only normal UI path that intentionally clears the saved token.
- Initial OAuth/App Remote consent, or consent after Spotify invalidates the
  authorization, still requires user interaction.

The old Persistent Text / Music Probe experiment is removed completely:

- its Media UI card is gone;
- `HudTextRendererProbe.swift` is removed;
- AppState no longer owns the probe;
- probe-only HudCommands helpers are removed;
- obsolete probe tests are removed.

The confirmed native HUD music-notification path and the independent
Music/Spotify popup enable/disable setting remain unchanged.


## v54 — explicitly exclude removed probe files from XcodeGen

The v53 source ZIP correctly removed `HudTextRendererProbe.swift`, but the CI
checkout still contained a stale copy of that file. Because `project.yml`
previously included the entire `HUDController` directory recursively, XcodeGen
picked up the stale local file and tried to compile it. That file referenced
probe-only HudCommands helpers that v53 correctly removed.

v54 makes deletion robust even when an updated repo is copied over an older
checkout instead of replacing it completely:

- `HUDController/Media/HudTextRendererProbe.swift` is explicitly excluded from
  the application target;
- old `V41TextRendererProbeTests.swift` and
  `AppStateInitializationOrderTests.swift` are explicitly excluded from the
  test target;
- the current v54 ZIP still does not contain those removed source files.

No runtime application behavior changed from v53.


## v55 — overwrite stale Git probe source safely

The v54 CI app/test targets compiled, but one v54 test failed because it required
`HudTextRendererProbe.swift` to be physically absent from the checkout.

That is not reliable when a repository is updated by copying a newer ZIP over
an older Git checkout: Git may retain a file that used to be tracked even when
the new ZIP omits it.

v55 makes the cleanup robust to that workflow:

- `project.yml` still explicitly excludes the removed probe source from the app
  target and excludes its old unit tests;
- an inert `HudTextRendererProbe.swift` compatibility shim is included at the
  former path so copying v55 over an older checkout overwrites the stale
  implementation;
- the shim contains no class, route enum, packet calls, or executable probe
  behavior;
- the regression test now accepts either physical absence or the known inert
  shim instead of treating file presence alone as failure;
- runtime AppState, MediaView, and HudCommands are additionally checked to make
  sure the removed probe does not return.

No runtime application behavior changed from v53/v52.


## v56 — Spotify fresh-App-Remote automatic recovery

Field logs showed a distinctive Spotify failure mode:

- authorization was successfully saved to Keychain;
- the App Remote later disconnected;
- the same long-lived `SPTAppRemote` repeatedly returned
  `com.spotify.app-remote -1000 Connection attempt failed`;
- after a fresh HUD Controller process was created, the Keychain token was
  restored and App Remote connected immediately.

v56 therefore treats the Spotify transport object as disposable while treating
authorization as persistent.

Changes:

- every foreground activation while disconnected creates a fresh
  `SPTAppRemote`, restores the Keychain token, and connects automatically;
- repeated connection failures also replace the App Remote automatically;
- rebuilding the transport never clears Spotify authorization;
- duplicate simultaneous `connect()` calls are suppressed with an
  `connectionInFlight` guard;
- callbacks from discarded App Remote generations are ignored;
- retry cadence is 1 s, 2 s, 5 s, 10 s, then 15 s indefinitely;
- successful connection always re-establishes the player-state subscription;
- player-state subscription itself retries up to four times;
- only explicit Re-authorize clears the stored token.

Spotify SDK limitation: plain `connect()` cannot silently wake Spotify if the
Spotify application is not running. Spotify's documented wake path is
`authorizeAndPlayURI`, which performs an app switch. Therefore v56 guarantees
automatic recovery when Spotify is available/running again, but it does not
silently bypass that iOS/Spotify app-switch requirement after Spotify has been
fully terminated.


## v57 — navigation/capture reliability + hidden music layout lab

Field-log driven changes:

### Physical HUD speed-limit boot style
A rectangular speed-limit packet with limit `0` is now sent immediately when
the HUD BLE transport/session becomes ready. This is a style-only/hidden prime:
it overwrites the firmware's circular boot default without intentionally
showing the previous road's stale speed limit. The real GPS/OSM limit replaces
it when available, and the normal phase-2/phase-3 rehydration still reasserts
the rectangular style.

### Apple Maps
- Simple arrow classification now uses the arrowhead region instead of total
  left/right pixel mass. The long stem on Apple's curved arrows was causing
  left turns to be classified as right turns.
- Pure numeric route-shield OCR is retained. A grayscale shield is represented
  as `US <number>` and a colored interstate-style shield as `I-<number>`.
- Example target: the supplied Apple card `1 / North` becomes `US 1 North`
  rather than only `North`.
- Existing lane-guidance highlighted-arrow handling remains.

### Google Maps
- Current distance/maneuver pairing is spatial when Vision boxes are
  available, so a current `100 ft` row is not paired with the next route
  instruction.
- HUD primary text is compacted (`Turn left`, `Turn right`, `Keep left`, etc.)
  while the road is kept separately. Long context such as
  `after the gas station (on the left)` no longer consumes the HUD line.
- `Destination will be on the left/right` with remaining distance is an active
  destination-approach state, not arrival and not an invalid OCR frame.

### ScreenCaptureKit
- Raw-frame watchdog threshold is 4 seconds.
- Any capture loss force-sends Navigation OFF independent of local
  `navigationModeArmed`, then reasserts OFF twice if capture has not recovered.
- When the cached content filter becomes unusable and iOS requires a new
  Entire Display selection, the app posts a local notification while
  backgrounded. Tapping the notification opens HUD Controller, where automatic
  capture startup presents Apple's system picker.
- iOS does not permit HUD Controller to draw its own arbitrary popup over
  Google Maps/Apple Maps; the system notification banner is the supported
  cross-app attention mechanism.

### Experimental persistent Spotify display
The original decompiled Android library exposes `PushMessageCommandPacket`:
command 2 / p1 24 / p2 0 with positions TOP, LEFT, DOWN, FULL and title/message
text. v57 adds an Experimental HUD Music Layout card to the Media page.

The lab can:
- send current Spotify artist + track through PushMessage;
- mirror future Spotify track changes through PushMessage;
- choose TOP / LEFT / DOWN / FULL;
- test notification timeout, line count, and `HudHUDWidgetsMiniState`;
- clear the experimental message.

No RIGHT enum exists in this hidden packet, so v57 does not invent one.
These are genuine firmware commands but their combined persistent-layout
behavior remains experimental.


## v58 — experimental Media binding compile fix

The v57 CI failure occurred only in the new Experimental HUD Music Layout UI.
`AppState.settings` is intentionally owned as a `let`, so Swift cannot synthesize
writable projected-value bindings such as
`$state.settings.experimentalMusicPosition`.

v58 keeps the same settings model and runtime behavior, but each experimental
Picker/Toggle/Stepper now uses an explicit `Binding(get:set:)` that reads and
writes the corresponding persisted `HudSettings` property.

No navigation, ScreenCaptureKit, Spotify, BLE, OBD, speed-limit, or protocol
behavior changed from v57.


## v59 — Apple Maps curved-arrow direction fix

A photo/screen-capture regression showed the same Apple Maps left-turn card
oscillating between Left, Straight, and Right depending on small Vision
bounding-box changes. The v57 upper-arrowhead heuristic was therefore not
geometrically stable.

v59 replaces it with an extreme-edge asymmetry invariant:

- a left-turn glyph has a narrow far-left arrow tip and a heavy far-right
  vertical stem/bend;
- a right-turn glyph is the horizontal mirror image;
- both edge pixel mass and edge vertical span must agree before declaring
  left/right;
- tall/balanced glyphs fall back to Straight;
- the existing highlighted-lane-guidance classifier remains separate.

The regression test includes measurements from the supplied Apple Maps
`0.4 mi / US 1 North` left-turn screenshot to ensure that exact geometry is
never interpreted as Right again.

No other v58/v57 behavior changed.


## v60 — isolate Apple maneuver glyph before direction classification

A second photo regression showed the lane-guidance case still classifying
correctly while every normal Apple maneuver was unstable or reversed:

- `US 1 North` left -> Right
- `Falls Bridge` right -> Straight
- highlighted-lane Lansdowne straight -> Straight (correct)
- `N 33rd St` left -> Right

The issue was therefore not the lane classifier and not OCR text. The normal
classifier was measuring every bright pixel in a crop anchored to Vision's
distance bounding box. Tiny bounding-box changes could let pieces of distance
text enter that crop and dominate the arrow geometry.

v60 now:

- threshold-crops the normal maneuver region as before;
- splits the bright pixels into 8-connected components;
- selects the dominant arrow-like component while penalizing leaked text on the
  right side;
- classifies only that isolated glyph;
- identifies tall isolated glyphs as Straight;
- classifies curved left/right glyphs from upper-half mass and centroid;
- leaves the already-working multi-lane highlighted-arrow path untouched.

The supplied screenshots were used as offline geometry checks: the simple
left, simple right, lane-guidance straight, and second simple-left examples
classify Left, Right, Straight, Left respectively with this component-isolated
method.


## v61 — update stale v59 Apple-arrow regression test

The v60 application target built successfully. CI failed only because the
older `V59AppleArrowDirectionTests` still searched the source for the v59
edge-asymmetry variables (`leftTipByMass`, `rightTipBySpan`, etc.).

Those variables were intentionally removed by v60's connected-component
rewrite.

v61 updates the regression test to verify the current invariant:

- isolate the bright maneuver glyph with `dominantArrowComponent`;
- score/select the likely arrow component;
- classify left/right from the isolated component's upper-half geometry;
- retain the center-shift fallback;
- ensure both the v57 upper-crop heuristic and v59 edge-tip heuristic remain
  absent.

No runtime application behavior changed from v60.


## v62 — Apple arrow + route-shield robustness

The v61 photo logs still showed left-turn cards being emitted as Right. v62
keeps v60's connected-component isolation but replaces the final direction
decision with the extreme-edge invariant measured directly from the supplied
screenshots:

- left turn: narrow/short left arrow-tip edge, tall/heavy right stem;
- right turn: narrow/short right arrow-tip edge, tall/heavy left stem;
- straight/lane-guidance remain separate paths.

The parser also now accepts route-shield OCR variants such as `13`, `/13`,
`{13}`, `(13)`, `US 13`, and a merged `13 N 38th St`. A shield-only OCR token
no longer becomes the road name and no longer prevents the parser from reading
the following actual street/direction text.

No unrelated runtime behavior changed from v61.


## v63 — stale Apple shield/component regression-test fix

The v62 application target built successfully and all new v62 tests passed.
CI failed only because two older tests still asserted behavior superseded by
v62.

- `V51FieldReliabilityTests` now expects the deliberately preserved route
  shield text `US 13 Powelton Ave`.
- `V60AppleArrowComponentIsolationTests` still verifies connected-component
  isolation, but its direction assertions now target v62's extreme-edge
  tip/stem classifier instead of the removed upper-half classifier.

No runtime application code changed from v62.


## v64 — Apple centroid direction + secondary shield OCR

Repeated photo tests showed that edge/upper-half heuristics remained unstable.
v64 keeps connected-component isolation but changes the final simple-arrow
classification to the whole component's horizontal centroid.

Measured directly from the supplied 1290x2796 Apple Maps screenshots:

- `0.4 mi / US 1 North` left-turn glyph: normalized centroid shift ≈ +0.054;
- `150 ft / US 13 Powelton Ave` right-turn glyph: shift ≈ -0.059.

The classifier uses a ±0.025 dead-band:
positive => Left, negative => Right, near zero => Straight.

This uses the actual stem mass of Apple's curved glyph instead of trying to
infer which extreme edge is the arrowhead.

Route shields also receive a second recovery path. If the normal Vision pass
finds road/direction text such as `North` but no numeric shield, v64 performs
one high-accuracy OCR request on a narrowly cropped region immediately to the
left of that text. It accepts short shield forms such as `1`, `/1`, `{1}`, and
`US 1`, then combines the recovered number with the road direction.

The experimental PushMessage music path is retained for comparison, but field
logs show no rendered text from it; only `HudHUDWidgetsMiniState` produced a
visible effect. No new persistence claims are made for that experiment.


## v65 — stale Apple regression-file cleanup

The v64 application target built successfully and all v64 tests passed.
The CI checkout nevertheless executed four older Apple-arrow regression files
from v59-v62, because ZIP-overlay repository updates do not necessarily delete
files that were tracked by an earlier Git commit.

v65 makes the project resilient to that update workflow:

- `project.yml` explicitly excludes the superseded v59-v62 Apple test files;
- v65 also ships inert overwrite shims at those exact old paths, so copying the
  new repository over an existing checkout replaces stale assertions even
  before XcodeGen runs;
- the active Apple-arrow/shield coverage remains in
  `V64AppleCentroidShieldRecoveryTests` and `V64AppleRoadFallbackTests`.

No runtime application behavior changed from v64.


## v66 — offline-validated Apple template classifier

The repeated geometric Apple-arrow heuristics were retired.

Before implementing v66, the supplied Apple Maps screenshots were analyzed
offline. Eleven clean Apple simple-arrow glyphs were extracted from the cards:

- 5 left turns
- 4 right turns
- 2 straight maneuvers

Each glyph was isolated, normalized to 96×96, and classified against median
left/right/straight shape templates with small ±4-pixel translation search.

Leave-one-out validation classified **11/11 correctly**.

Typical IoU:
- correct template: ~0.97–1.00
- wrong templates: ~0.19–0.26

v66 embeds those canonical binary templates directly in Swift, so no external
asset/resource loading is required. An unknown/poorly captured glyph must score
at least 0.62 and beat the second-best class by at least 0.16; otherwise the
classifier returns Straight rather than confidently guessing the opposite turn.

Apple multi-lane guidance retains its separate highlighted-white-lane parser.

### Spotify persistent experiment cleanup

Field testing showed that the hidden PushMessage command packets were
transmitted but did not render persistent artist/track text. The experimental
Spotify layout/settings card and its runtime mirroring/settings have therefore
been removed from the application UI.

The confirmed native Spotify music notification path and automatic Spotify
reconnection remain unchanged.

The hidden protocol helpers are left in `HudCommands` for future controlled
reverse-engineering. Candidate future directions include testing whether an
existing firmware widget can be repurposed at the packet level, but numeric
widgets such as average speed/distance are likely to accept structured numeric
payloads rather than arbitrary strings and are not presented as working music
solutions in v66.


## v67 — Apple lane-guidance gate fix

The v66 template masks were validated offline, but field logs still showed
ordinary Apple route cards classified incorrectly before BLE serialization.

Root cause: `classifyHighlightedLaneArrow` ran BEFORE the normal template
classifier and could return a maneuver for a normal single-arrow card. Because
that returned immediately, the validated left/right/straight template matcher
never executed.

v67 changes the lane path so it is eligible only when the screen contains an
actual multi-lane signature:

- a lower luminance threshold detects Apple's gray inactive lane arrows;
- connected components are extracted;
- at least 3 substantial arrow-like components must be present;
- the components must span at least 28% of the card width;
- only then is the bright white active lane arrow classified.

Normal single-arrow cards therefore fall through to the v66 template matcher.

This change is upstream of HUD packet generation. `HudManeuver.direction`
mapping was inspected and remains correct:
Right=2, Straight=4, Left=6.


## v68 — Apple right-turn acceptance + stronger US shield recovery

Field results after v67:

- left-turn cards now classify correctly;
- a genuine right-turn card (`US 13 Powelton Ave`) still fell back to Straight;
- `0.4 mi` cards parse correctly as 644 m, but the HUD firmware displays that
  meter value as ~2112 ft in imperial mode;
- `US 1 North` sometimes still loses the shield number entirely.

v68 changes the Apple template decision so Left/Right candidates can be
accepted at a lower absolute IoU when they still beat the next template by a
clear margin. Straight keeps a stricter threshold.

Shield recovery now tries four ROIs of increasing width, upscales the crop 4x,
uses Vision `.accurate`, lowers minimum text height, checks up to 10 candidates,
and explicitly seeds common route strings.

Important distance note: no OCR distance change was made. The log proves
`0.4 mi` is parsed as 644 m. The physical HUD itself converts the meter field to
feet and renders ~2112 ft. Preserving `0.4 mi` exactly requires identifying a
firmware/unit-display control in the navigation packet rather than changing OCR.


## v69 — stale v66 template-regression test fix

The v68 application target built successfully. Both v68 tests passed.

CI failed only because `V66AppleTemplateClassifierTests` still asserted the
original v66 template thresholds (`0.62` absolute score and `0.16` margin).
v68 intentionally replaced those values with separate turn and straight
acceptance thresholds.

v69 updates that old test to validate the current v68 template pipeline and
adds a less brittle guard that checks the classifier architecture without
pinning future tests to obsolete threshold constants.

No runtime application code changed from v68.


## v70 — original HUD imperial-unit command + US-1 visual fallback

Field logs show Apple OCR distances are correct before BLE serialization:

- 2.3 mi -> 3701 m
- 150 ft -> 46 m
- 80 ft -> 25 m
- 0.4 mi -> 644 m

The original decompiled Android app reveals that every HUD settings restore
also sends `DisplaySpeedUintsCommandPacket`:

- CommandPacket p1 = 9
- p2 = 5
- int32 type = 0 metric / 1 imperial

Our iOS port had never implemented this command. v70 sends imperial type 1
during base rehydration, persisted-state rehydration, display reassert, and
immediately before each maneuver. This follows the original app rather than
artificially changing correct meter distances to compensate for HUD formatting.

For Apple `US 1 North`, Vision sometimes returns only `North`. v70 keeps the
multi-ROI accurate OCR recovery and adds a conservative visual fallback: if
shield OCR still fails, it examines the near-white connected component inside
the shield ROI and recognizes a narrow/tall centered digit-1 shape.

All v69 Apple arrow-template behavior is preserved.


## v71 — preserve exact OCR distance + correct US-1 numeral polarity

Screenshot-test logs showed:

- `80 ft` was correctly OCR-parsed to 25 m, but the Navigation UI converted
  25 m back to `82 ft`;
- `90 ft` became 28 m and was shown as `91 ft`;
- `0.4 mi` remained correctly parsed as 644 m;
- `US 1 North` still returned only `North`.

The first issue was a UI round-trip problem, not OCR. `NavigationInstruction`
now carries the exact source distance string alongside the protocol meter
value. Apple/Google parsers populate it, and the Navigation UI displays that
original string exactly. Thus screenshot tests show `80 ft`, `90 ft`, `0.4 mi`,
etc. without integer-meter quantization artifacts.

The v70 US-1 visual fallback also had a polarity error: it assumed Apple's
route numeral was white. The actual Apple US shield is light with a dark
numeral. v71 first isolates the compact light shield body, then searches inside
it for a centered narrow/tall dark component representing digit `1`.

The physical HUD maneuver protocol still receives integer meters, matching the
original Android packet. Exact physical-HUD formatting is therefore a separate
firmware/protocol question from the screenshot-test UI.


## v72 — stale v70 US-1 regression-test fix

The v71 application target built successfully and all new v71 tests passed.

CI failed only because `V70ImperialUnitsAndUS1Tests` still asserted the old v70
US-1 heuristic, including the obsolete narrow/tall white-digit threshold.
v71 intentionally replaced that logic after identifying the polarity mistake:
Apple's US-route shield is light and its numeral is dark.

v72 updates the old regression test to verify the current light-shield /
dark-numeral fallback architecture and adds a less brittle guard that does not
pin future tests to the removed v70 geometry constant.

No runtime application behavior changed from v71.


## v73 — road field reliability

### Screen capture is the master navigation state
- no live/recent ScreenCaptureKit frame => HUD Freeride;
- HUD/BLE reconnect cannot re-arm a cached maneuver unless capture is healthy;
- watchdog runs every second and treats a raw frame older than 3 s as failure;
- while capture is desired but absent, Freeride is continuously reasserted and
  automatic capture recovery is driven.

### Original HUDWAY speed-limit road matcher
The decompiled Android `SpeedLimitEngine.kt` was ported more literally:
- Overpass 400 m query and 300 m refresh distance;
- original 30 m road-segment eligibility construction;
- candidate ranking:
  `(angle < 45 ? angle/45 : 2) + (distance < 15 ? distance/15 : 2)`;
- reverse road bearing is not considered equivalent;
- internal maxspeed remains km/h and is converted to mph at the same final
  boundary used by the original HUDWAY navigation manager.

This replaces our old approximate 45 m nearest-road matcher, which could select
a nearby parallel/intersecting road's speed limit.

### Google merge
A current Google instruction containing `merge` now maps to the HUD Straight
maneuver instead of being interpreted as a left/right turn or skipped for the
next route block.

### Ambient BLEDOM
- scanning starts even with a remembered peripheral;
- GATT connection and advertisement discovery run as a hybrid;
- a connection stuck in `.connecting` for >6 s is cancelled/retried;
- healthy presence periodically reasserts HUD Auto Brightness ON;
- HUD reboot/reconnect no longer requires manually toggling Auto Enable.


## v74 — stale capture regression-test fix

The v73 app target builds successfully and the new v73 road-reliability tests
pass. CI failed only because two older tests still asserted pre-v73 capture
behavior.

- `V44HUDSessionRehydrationTests` previously expected a HUD reboot to always
  re-arm cached navigation. It now verifies the v73 invariant that
  ScreenCaptureKit health must be checked first; unhealthy capture forces
  Freeride.
- `V57NavigationCaptureMusicLabTests` previously pinned the watchdog to
  `age > 4`. v73 intentionally tightened the raw-frame threshold to 3 seconds.

No runtime application code changed from v73.


## v75 — legal speed-limit display + Spotify wake without reauthorization

### Speed-limit +5 display correction

Field logs showed the new original-style OSM matcher selecting the correct
legal speed, but the HUD sign was always five mph higher. The cause was the
persisted warning tolerance being transmitted inside
`HudSpeedLimitAndToleranceCommandPacket`.

Example from the field log:

`Speed limit 25 mph (+5)` with packet fields `limit=25, tolerance=5`.

On this physical HUD firmware that tolerance is reflected in the displayed
sign. v75 therefore separates the two concepts:

- legal speed-limit sign packet: `limit=<legal limit>, tolerance=0`;
- overspeed warning packet: `<legal limit> + user warning tolerance`.

The existing +5 user setting remains useful as an overspeed-warning threshold
without changing the number printed inside the speed-limit sign.

### Spotify connection versus authorization

The field log proves authorization was not lost in the garage. HUD Controller
restored the App Remote token from Keychain on every retry, while `connect()`
returned Spotify error -1000. Later, tapping Re-authorize invoked
`authorizeAndPlayURI("")`, Spotify opened, and App Remote connected.

Spotify's iOS SDK documents these as separate states: a saved access token can
remain valid while plain `connect()` cannot wake a non-running Spotify process.

v75 adds **Open Spotify / Resume Connection**, which calls the Spotify app-switch
path while preserving the existing Keychain token. The destructive action is
renamed **Reset Spotify Authorization** and remains available only as a
troubleshooting fallback.

Normal reconnect/retry behavior still never clears authorization.


## v76 — capture crash/stall stability

This release intentionally focuses on the navigation crash/stall issue before
further speed-warning or distance tuning.

Field evidence:
- two drive logs end abruptly without a normal app lifecycle shutdown;
- in the final long session, after raw ScreenCaptureKit frames stopped, recovery
  reached more than 200 attempts;
- the watchdog kept comparing against a frame timestamp hundreds of seconds old;
- ambient BLE scanning was also being reissued/logged continuously.

Changes:
- ScreenCaptureKit recovery is serialized: only one recovery chain can run;
- watchdog/error/foreground recovery requests are coalesced;
- every new SCStream clears the previous stream's `lastFrameAt`;
- a newly started stream is not declared stale before its first frame arrives;
- a successful frame resets recovery backoff;
- retry cadence is bounded at 1, 2, 4, 8, then 15 seconds;
- capture-health Freeride invariant remains unchanged;
- ambient BLE scanning is idempotent: one continuous CoreBluetooth scan rather
  than reissuing scan calls every 500 ms.

No intentional change was made to OCR distance conversion or overspeed-warning
semantics in this crash-focused build.


## v77 — combined crash stability + exact distance visibility + gauge warning

### Distance investigation

Drive logs prove OCR/update cadence is correct. Example Falls Bridge sequence:

- 2.7 mi -> 4345 m -> maneuver sent
- 2.6 mi -> 4184 m -> maneuver sent
- 2.5 mi -> 4023 m -> maneuver sent
- 2.4 mi -> 3862 m -> maneuver sent
- 2.3 mi -> 3701 m -> maneuver sent
- 2.2 mi -> 3541 m -> maneuver sent

The original decompiled `HudManeuverCommandPacket` contains only:

`writeInt(distance)`

and the stock navigation manager sends `(int) distanceAlongStep` in meters.
There is no float-distance or distance-text field in this packet.

The physical HUD firmware itself therefore performs the imperial formatting.
Observed firmware behavior is coarse (e.g. decimal miles collapse to whole
miles and small feet values collapse to coarse ~100-ft buckets).

v77 keeps the native meter field correct but additionally inserts the exact
source OCR distance into the first maneuver text line:

- `Right • 2.4 mi`
- `Straight • 80 ft`
- `Right • 150 ft`

The dedicated firmware distance area may still show its coarse value, but the
exact Maps value is now visible without firmware modification.

Feet conversion now uses nearest-meter rounding (`ft * 0.3048`) rather than
the earlier ceiling workaround.

### Overspeed warning

The legal speed-limit sign remains `tolerance=0`.

The user's tolerance is applied only through
`DisplaySpeedWarningCommandPacket` (`p1=9, p2=9`) at:

`legal speed limit + configured tolerance`

which is the firmware path intended to trigger the speed-gauge warning state /
warning color. Changing the tolerance immediately reasserts the legal sign and
the gauge threshold.

### Crash reliability

All v76 serialized ScreenCaptureKit recovery and idempotent ambient scanning
changes are retained.


## v78 — stale regression-test cleanup

The v77 application target builds successfully. The CI failures were all old
source-string assertions that predated the v76/v77 architecture changes.

Updated tests:
- V51 now verifies nearest-integer-meter conversion plus preserved exact source
  distance text instead of the removed upward `ceil()` bias.
- V57/V73/V74 now validate the serialized v76 watchdog wording/state rather
  than the obsolete `no active stream/frame` string.
- V75 now validates the v77 `sendOverspeedGaugeThreshold` helper instead of
  expecting duplicated inline `limit + tolerance` expressions.

No runtime application behavior changed from v77.


## v79 — TestFlight Release compile fix

The v78 iOS CI path passed, but the TestFlight physical-device archive failed
in `ExternalNavigationCapture.swift`.

Xcode 27 Release compilation requires explicit `self` for captured instance
properties inside the `SCStream.startCapture` completion closure.

Fixed:

- `recoveryAttempt = 0` -> `self.recoveryAttempt = 0`
- `recoveryInFlight = false` -> `self.recoveryInFlight = false`

No runtime behavior changed from v78.


## v80 — Google "Use the ... lane to merge" current-card fix

A supplied Google Maps route-list screenshot exposed a gap between two parser
stages.

The maneuver classifier already mapped any text containing `merge` to the HUD
Straight maneuver before checking left/right words. However,
`isExplicitGoogleManeuver()` only accepted text that *started* with `merge`.

Google's actual current card was:

- `In 0.1 mi`
- `Use the left lane to merge onto Eakins Ovl/...`

Because that instruction starts with `Use the...`, the explicit-maneuver gate
discarded it. The parser then continued down the route list and selected a later
`200 feet` left-turn card.

v80 recognizes `Use the left/right lane to merge ...` as an explicit Google
maneuver. It therefore pairs the top 0.1-mi distance with the top merge
instruction, after which the existing merge-before-left classifier correctly
maps it to Straight.

A regression test reproduces the supplied multi-card screenshot and requires:
`0.1 mi + merge -> Straight`, never the following 200-ft left turn.


## v81 — Google merge regression-test access fix

The v80 application target builds successfully. iOS CI failed while compiling
the test target because three new white-box tests directly called
`fileprivate` parser helpers:

- `isExplicitGoogleManeuver`
- `maneuverFromText`

Those helpers remain private. v81 removes the invalid direct-access tests and
keeps end-to-end tests through the public `ExternalNavigationOCRParser.parse`
surface.

The supplied route-list regression still requires the top current card:

`In 0.1 mi + Use the left lane to merge ...`

to parse as **Straight at 0.1 mi**, rather than selecting the following
200-ft left turn.

No runtime application code changed from v80.

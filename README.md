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

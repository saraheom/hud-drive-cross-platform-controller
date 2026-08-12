# HUDWAY Cross-Platform Controller

A GitHub-first development repository for understanding and testing the HUDWAY Drive hardware BLE protocol before implementing production Android and iOS clients.

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
6. After the workflow succeeds, open its run and download the `HUDWAY-BLE-Tester-Windows` artifact.
7. Extract and run `HUDWAY_BLE_Tester.exe` on a Windows computer with Bluetooth LE.

GitHub Actions artifacts preserve build outputs after the job completes. The workflow uses a Windows runner, installs the pinned Python dependencies, runs protocol tests, builds the GUI with PyInstaller, and uploads both the `.exe` and a ZIP. 

### Build locally on Windows

```powershell
cd windows
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
python -m pytest ..\tests -q
pyinstaller --clean --noconfirm HUDWAY_BLE_Tester.spec
```

Output:

```text
windows/dist/HUDWAY_BLE_Tester.exe
```

## Future Android workflow

`.github/workflows/android-build.yml` is already included. It remains inactive until an Android Gradle wrapper exists under `android/`. When the Android project is added, pushes touching `android/**` will build and upload a debug APK.

## Future iOS workflow

`.github/workflows/ios-build.yml` is included for an Expo/EAS project. It remains inactive until `ios/package.json` and `ios/eas.json` exist. Add an Expo access token as the GitHub Actions secret `EXPO_TOKEN` before running iOS cloud builds.

## Safety

Test while parked. Do not interact with this software while driving. Keep the original HUDWAY application disconnected during protocol tests because the HUD may accept only one BLE central connection.

## Windows BLE scan diagnostics

The Windows build now publishes two executables:

- `HUDWAY_BLE_Tester.exe` — normal GUI build.
- `HUDWAY_BLE_Tester_Diagnostic.exe` — same GUI plus a console window for WinRT/Bleak diagnostics.

When **Scan** is clicked, the GUI log must immediately show `SCAN BUTTON: clicked`, then `Starting BLE scan...`, then discovery events. The dropdown is intentionally **not HUDWAY-only**; it displays every BLE advertiser returned by Windows. Nordic UART Service advertisers are marked with a star when that UUID is present in the advertising packet.

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
- validated HUDWAY BLE protocol and connection watchdog;
- serialized 19-byte transport;
- manual and simulated navigation pipeline;
- HUD-style dashboard controls;
- persistent shareable logs;
- Shortcuts/App Intents scaffold;
- GitHub Actions for simulator CI, signed Ad Hoc IPA, and TestFlight.

See `docs/IOS_APPLE_DEVELOPER_SETUP.md`.

## v11 iOS CI test-host correction

The visible app label remains `HUDWAY Controller` through `CFBundleDisplayName`,
but the executable product now keeps the target name `HUDWAYController`. This
matches XcodeGen's generated unit-test host path and avoids the prior
`Could not find test host` error.


## v12 — iPhone notifications / ANCS configuration

The iOS client now implements the HUD firmware's notification configuration
packets discovered in the decompiled client: global enable, filter
initialization, per-app filters, notification timeout, and message-line count.

A Maps experiment section enables Google Maps, Apple Maps, and Waze filters for
hardware testing. Classic ANCS remains accessory-facing: HUDWAY Drive receives
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
- marks HUDWAY Controller as iPhone-only (`TARGETED_DEVICE_FAMILY = 1`);
- declares supported iPhone orientations;
- uses the modern `UILaunchScreen` Info.plist declaration.

This avoids the previous iPad multitasking validation path and satisfies
Apple's current SDK minimum for App Store Connect uploads.


## v15 — iOS HUD discovery correction

The iPhone scanner no longer requires the HUDWAY Nordic UART Service UUID to
appear in the BLE advertisement. Physical Windows testing showed HUDWAY Drive
can advertise only its local name and expose NUS after GATT connection.

iOS now:
- scans all BLE advertisements;
- logs every discovery including advertised service UUIDs;
- shows named peripherals in the picker;
- sorts HUDWAY-named devices first;
- automatically selects the first HUDWAY device;
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

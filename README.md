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

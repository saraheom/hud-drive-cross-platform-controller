# HUD Controller iOS

Native SwiftUI iOS client for the validated HUD Drive BLE protocol.

## v90.26 field-fix baseline

The current build uses admitted-member-aware ambient synchronization, a bounded post-crank engine-start reacquisition window, completed-turn road takeover, OSM same-road corridor consensus, and Philadelphia Street Centerline `POSTED_SPEED_LIMIT` / `SPEED_LIMIT` data for faster new-road limit acquisition. See `../docs/V90_26_AMBIENT_SPEED_ACQUISITION.md`.

## v0.1 features

- CoreBluetooth HUD discovery and connection
- NUS service/characteristic discovery
- UART connection-check handshake and automatic keep-alive response
- Serialized 19-byte BLE writes
- HUD initialization sequence
- Auto/manual brightness
- Dashboard presets
- Time/weather panel control
- Navigation ON/OFF
- Manual maneuver editor
- Five-leg navigation simulator
- Persistent session logs in `Documents/HUD Logs`
- Share/export log files
- App Intents / Shortcuts scaffold
- Notification settings UI scaffold for later ANCS filter packet validation

## Generate Xcode project

This repository intentionally stores an XcodeGen `project.yml` instead of a generated
`.xcodeproj` so GitHub can generate it deterministically.

```bash
brew install xcodegen
export HUD_BUNDLE_ID=com.yourname.hudcontroller
cd ios
xcodegen generate
```

GitHub Actions does this automatically.

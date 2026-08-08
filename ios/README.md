# HUDWAY Controller iOS

Native SwiftUI iOS client for the validated HUDWAY Drive BLE protocol.

## v0.1 features

- CoreBluetooth HUDWAY discovery and connection
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
- Persistent session logs in `Documents/HUDWAY Logs`
- Share/export log files
- App Intents / Shortcuts scaffold
- Notification settings UI scaffold for later ANCS filter packet validation

## Generate Xcode project

This repository intentionally stores an XcodeGen `project.yml` instead of a generated
`.xcodeproj` so GitHub can generate it deterministically.

```bash
brew install xcodegen
export HUDWAY_BUNDLE_ID=com.yourname.hudwaycontroller
cd ios
xcodegen generate
```

GitHub Actions does this automatically.

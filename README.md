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

# v90.35.3.11.1 CI alignment

The GitHub Actions/Xcode 26 workflow successfully compiled v90.35.3.11 and ran 282 XCTest cases. The only failure was `SpeedUnitTests.testVehicleViewUsesMPHLabels`, whose legacy source-string assertion required `VehicleView.swift` to contain no literal `km/h`.

v90.35.3.11 intentionally adds passive OBD protocol-forensics help text describing simultaneous GPS `mph/km/h` candidates. The production GPS speed and speed-limit labels still bind `currentSpeedMph` and `currentSpeedLimitMph` as mph.

This revision changes only `ios/HUDControllerTests/SpeedUnitTests.swift` plus release documentation. Production `ios/HUDController/` sources are byte-for-byte unchanged from v90.35.3.11. U2W v8.15.1 is unchanged.

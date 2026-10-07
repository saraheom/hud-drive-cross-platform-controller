import XCTest

final class V90352421HardBoundedMirrorOBDFlightTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testV2421PairsWithV834HardBoundedMirror() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(video.contains("v8.34-hard-bounded-mirror-v831-raw-tcp-15332"))
        XCTAssertTrue(video.contains("U2WH2648"))
        XCTAssertTrue(app.contains("appVersion=v90.35.3.24.27"))
        XCTAssertTrue(app.contains("paired_u2w=v8.37 Forensic Seam Capture + unchanged v8.35 helper (injection deferred) + unchanged v8.34 Hard-Bounded Mirror + exact v8.31 Raw Relay"))
        XCTAssertFalse(ui.contains("pairs with U2W v8.37"))
    }

    func testWholeDriveOBDRecorderIsPassiveAndAutomatic() throws {
        let bluetooth = try source("HUDController/Bluetooth/HudBluetoothManager.swift")
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(bluetooth.contains("Armed — starts automatically with HUD OBD"))
        XCTAssertTrue(bluetooth.contains("recordOBDDriveRX(data)"))
        XCTAssertTrue(bluetooth.contains("drive_raw_ble.bin"))
        XCTAssertTrue(bluetooth.contains("gps_reference.csv"))
        XCTAssertTrue(app.contains("collectOBDDriveDiagnosticBundle()"))
        // v24.27 hides the legacy whole-drive OBD probe controls from the Map Mode card.
        XCTAssertFalse(ui.contains("Collect OBD Drive Diagnostic ZIP (parked)"))
        XCTAssertFalse(ui.contains("sends no repeated hidden-item stimulus"))
        XCTAssertTrue(ui.contains("Collect Live Map Diagnostic ZIP (parked)"))
    }
}

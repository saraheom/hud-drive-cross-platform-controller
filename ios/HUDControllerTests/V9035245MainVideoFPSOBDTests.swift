import XCTest
@testable import HUDController

final class V9035245MainVideoFPSOBDTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testMainVideoRecoveryIsBoundedBeforeFreshIDRWait() throws {
        let text = try source("ios/HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(text.contains("recentAnchorRecoveryUsed"))
        XCTAssertTrue(text.contains("WAITING_FRESH_IDR"))
        XCTAssertTrue(text.contains("TCP PRESERVED, quarantining replay and waiting for next live IDR"))
    }

    func testFPSProbeOffersExpectedCadences() throws {
        let text = try source("ios/HUDController/Models/HudMapModeSettings.swift")
        XCTAssertTrue(text.contains("supportedHUDFrameRates = [5, 8, 10, 12, 15]"))
        XCTAssertTrue(text.contains("HUD.MapMode.hudFrameRate"))
    }

    func testOBDProbeKeepsGPSDisplayAndReportsPID0D() throws {
        let app = try source("ios/HUDController/App/AppState.swift")
        let obd = try source("ios/HUDController/Vehicle/HudOBDController.swift")
        XCTAssertTrue(app.contains("GPS display unchanged"))
        XCTAssertTrue(app.contains("fullscreen=unchanged"))
        XCTAssertTrue(obd.contains("vehicleSpeedPIDSupported"))
    }
}

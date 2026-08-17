import XCTest
@testable import HUDController

final class V51FieldReliabilityTests: XCTestCase {
    func testAppleDestinationSidePhraseCountsAsArrival() {
        let result = ExternalNavigationOCRParser.parse(
            lines: ["The destination is on your right: 4442 Ridge Ave, Philadelphia", "End Route"],
            rawText: ""
        )
        XCTAssertEqual(result.source, .appleMaps)
        XCTAssertEqual(result.screenState, .arrived)
        XCTAssertEqual(result.instruction.maneuver, .destination)
    }

    func testFeetConversionUsesNearestIntegerMeterAndPreservesExactText() {
        let result = ExternalNavigationOCRParser.parse(
            lines: ["500 ft", "Ridge Ave", "900 ft", "River Ridge Ct", "End Route"],
            rawText: ""
        )
        XCTAssertEqual(result.source, .appleMaps)
        XCTAssertEqual(result.instruction.distanceMeters, 152)
        XCTAssertEqual(result.instruction.displayDistanceText, "500 ft")
    }

    func testRouteShieldNoiseIsRemoved() {
        let result = ExternalNavigationOCRParser.parse(
            lines: ["150 ft", "{13} Powelton Ave", "450 ft", "N 33rd St", "End Route"],
            rawText: ""
        )
        XCTAssertEqual(result.instruction.streetName, "US 13 Powelton Ave")
    }

    func testCaptureInvalidatesRepeatedlyFailingFilter() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/ExternalNavigationCapture.swift")
        let source = try String(contentsOf: url)
        XCTAssertTrue(source.contains("cachedFilterFailureCount >= 3"))
        XCTAssertTrue(source.contains("lastFilter = nil"))
        XCTAssertTrue(source.contains("needsUserReselection = true"))
        XCTAssertTrue(source.contains("Raw stream heartbeat"))
    }

    func testAmbientTimeoutSetterDoesNotSelfAssignInDidSet() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/AmbientLightMonitor.swift")
        let source = try String(contentsOf: url)
        XCTAssertTrue(source.contains("func setAbsenceTimeout"))
        XCTAssertFalse(source.contains("didSet {\n            absenceTimeoutSeconds ="))
    }

    func testMusicPopupPreferencePersists() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HUDController/Models/HudSettings.swift")
        let source = try String(contentsOf: url)
        XCTAssertTrue(source.contains("HUD.Settings.notifyMusic"))
    }

    func testOBDRetryLoopUsesGenerationToken() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/HudOBDController.swift")
        let source = try String(contentsOf: url)
        XCTAssertTrue(source.contains("autoConnectGeneration"))
        XCTAssertTrue(source.contains("generation == self.autoConnectGeneration"))
    }
}

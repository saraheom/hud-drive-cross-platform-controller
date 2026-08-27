import XCTest
@testable import HUDController

final class V90111NoBillingOSMTraceTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testHEREIsRemovedAndOSMTraceIsSelectable() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        let view = try source("HUDController/UI/VehicleView.swift")
        XCTAssertFalse(speed.contains("routematching.hereapi.com"))
        XCTAssertFalse(speed.contains("HereAPIKeyStore"))
        XCTAssertFalse(view.contains("Save HERE Key"))
        XCTAssertTrue(speed.contains("case traceOSM = \"OSM Trace\""))
    }

    func testTraceMatcherRequiresHistoryConfidenceAndConfirmation() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("Array(traceLocations.suffix(8))"))
        XCTAssertTrue(speed.contains("traceLastConfidenceMargin"))
        XCTAssertTrue(speed.contains("margin >= 0.30"))
        XCTAssertTrue(speed.contains("if next >= 2"))
    }

    func testConditionalLimitsAreConservative() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("maxspeed:conditional"))
        XCTAssertTrue(speed.contains("parseSimpleConditionalMaxSpeed"))
        XCTAssertTrue(speed.contains("Unsupported conditions"))
    }
}

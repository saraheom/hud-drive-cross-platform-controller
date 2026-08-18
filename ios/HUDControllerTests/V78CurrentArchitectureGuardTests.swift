import XCTest
@testable import HUDController

final class V78CurrentArchitectureGuardTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    func testCurrentCaptureRecoveryArchitecture() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        XCTAssertTrue(source.contains("recoveryInFlight"))
        XCTAssertTrue(source.contains("serialized recovery attempt="))
        XCTAssertTrue(source.contains("watchdog sees no active stream"))
    }

    func testCurrentDistanceArchitecture() throws {
        let parser = try source(
            "HUDController/Navigation/GoogleMapsOCRParser.swift"
        )
        let commands = try source(
            "HUDController/Protocol/HudCommands.swift"
        )

        XCTAssertTrue(parser.contains("value * 0.3048"))
        XCTAssertTrue(commands.contains("normalizedSourceDistanceText"))
        XCTAssertTrue(commands.contains("primaryWithDistance"))
    }

    func testCurrentOverspeedArchitecture() throws {
        let source = try source(
            "HUDController/Vehicle/OriginalSpeedLimitEngine.swift"
        )

        XCTAssertTrue(source.contains("tolerance: 0"))
        XCTAssertTrue(source.contains("sendOriginalAutomaticSpeedWarning"))
        XCTAssertTrue(source.contains("HudCommands.speedWarningThreshold(legalLimitMph)"))
        XCTAssertFalse(source.contains("speedTolerance"))
    }
}

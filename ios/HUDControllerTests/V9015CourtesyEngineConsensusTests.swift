import XCTest
@testable import HUDController

final class V9015CourtesyEngineConsensusTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testEngineDiagnosticsDoNotGateLightPowerOnAnimation() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("hudEnginePowerSignalPresent"))
        let parts = monitor.components(separatedBy: "private func runStartupAnimationIfNeeded")
        XCTAssertGreaterThan(parts.count, 1)
        let block = parts[1].components(separatedBy: "private func queuePowerUpBreath")[0]
        XCTAssertFalse(block.contains("enginePowerPresent"))
        XCTAssertFalse(block.contains("vehicleStartupCompleted"))
        XCTAssertFalse(block.contains("headlightPowerSessionActive"))
    }

    func testCourtesyPowerCanAnimateLikeAnyOtherFreshPowerOn() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")

        let startupParts = monitor.components(separatedBy: "private func runStartupAnimationIfNeeded")
        XCTAssertGreaterThan(startupParts.count, 1)
        let startupBlock = startupParts[1].components(separatedBy: "private func queuePowerUpBreath")[0]
        XCTAssertFalse(startupBlock.contains("enginePowerPresent"))
        XCTAssertFalse(startupBlock.contains("vehicleStartupCompleted"))
        XCTAssertFalse(startupBlock.contains("headlightPowerSessionActive"))

        let didConnectParts = monitor.components(separatedBy: "didConnect peripheral: CBPeripheral")
        XCTAssertGreaterThan(didConnectParts.count, 1)
        let didConnectBlock = didConnectParts[1].components(separatedBy: "nonisolated func centralManager")[0]
        XCTAssertTrue(didConnectBlock.contains("animatedConnectionSession.remove(id)"))
    }
}

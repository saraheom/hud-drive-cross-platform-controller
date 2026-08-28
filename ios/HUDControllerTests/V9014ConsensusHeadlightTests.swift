import XCTest
@testable import HUDController

final class V9014ConsensusHeadlightTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testMixedHeadlightEvidencePreservesLastConfirmedDayNightMode() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("case bothOn"))
        XCTAssertTrue(monitor.contains("case bothOff"))
        XCTAssertTrue(monitor.contains("case mixed"))
        XCTAssertTrue(monitor.contains("Headlight consensus candidate=mixed; preserving confirmed"))
    }

    func testConsensusHasNoEngineStartupGate() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let pieces = monitor.components(separatedBy: "private func scheduleHeadlightConsensusEvaluation")
        XCTAssertGreaterThan(pieces.count, 1)
        let block = pieces[1].components(separatedBy: "private func commitConfirmedHeadlightPower")[0]
        XCTAssertFalse(block.contains("enginePowerPresent"))
        XCTAssertFalse(block.contains("vehicleStartupCompleted"))
    }
}

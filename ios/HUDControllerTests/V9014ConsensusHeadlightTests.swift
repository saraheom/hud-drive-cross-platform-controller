import XCTest
@testable import HUDController

final class V9014ConsensusHeadlightTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testHeadlightRequiresStableTwoControllerConsensus() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private enum HeadlightConsensusObservation"))
        XCTAssertTrue(monitor.contains("case bothOn"))
        XCTAssertTrue(monitor.contains("case bothOff"))
        XCTAssertTrue(monitor.contains("case mixed"))
        XCTAssertTrue(monitor.contains("both Center + Dashboard stable ON"))
        XCTAssertTrue(monitor.contains("both Center + Dashboard stable OFF"))
        XCTAssertTrue(monitor.contains("preserving confirmed"))
        XCTAssertFalse(monitor.contains("setAuthoritativeHeadlightPower"))
    }

    func testHeadlightBreathWaitsForBothGATTControllers() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private func tryStartConfirmedHeadlightBreath"))
        XCTAssertTrue(monitor.contains("dashboardGATTNotReady"))
        XCTAssertTrue(monitor.contains("centerGATTNotReady"))
        XCTAssertTrue(monitor.contains("Consensus headlight animation admitted"))
        XCTAssertTrue(monitor.contains("Same-epoch headlight reconnect → steady restore"))
        XCTAssertTrue(monitor.contains("restoreDeviceState(id)"))
    }

    func testV9010TransportBaselineRemains() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private var bledimSequenceByID: [UUID: UInt8]"))
        XCTAssertTrue(monitor.contains("protocolPacing=20Hz/rawBLEDIM"))
        XCTAssertTrue(monitor.contains("private func sendPowerWhenReady"))
        XCTAssertFalse(monitor.contains("Steady-state recovery begin"))
        XCTAssertFalse(monitor.contains("BLEDIM10Hz"))
    }
}

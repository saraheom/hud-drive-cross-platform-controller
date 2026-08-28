import XCTest
@testable import HUDController

final class V90151AnimationAbortFailsafeTests: XCTestCase {
    private func monitorSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("HUDController/Vehicle/AmbientLightMonitor.swift"),
            encoding: .utf8
        )
    }

    func testCancelledAnimationsHaveOneShotSteadyFailsafe() throws {
        let monitor = try monitorSource()
        XCTAssertTrue(monitor.contains("private func scheduleAnimationAbortFailsafe"))
        XCTAssertTrue(monitor.contains("brightness transition cancelled"))
        XCTAssertTrue(monitor.contains("Breath participation cancelled"))
        XCTAssertTrue(monitor.contains("Animation/fade aborted at transient level → restoring steady state"))
        XCTAssertTrue(monitor.contains("self.restoreDeviceState(id)"))
    }

    func testFailsafeYieldsToNewerOperations() throws {
        let monitor = try monitorSource()
        let block = monitor.components(separatedBy: "private func scheduleAnimationAbortFailsafe")[1]
            .components(separatedBy: "private func animationWriteInterval")[0]
        XCTAssertTrue(block.contains("Task.sleep(for: .milliseconds(180))"))
        XCTAssertTrue(block.contains("self.activeBreathIDs.contains(id)"))
        XCTAssertTrue(block.contains("self.breathPrepareTasks[id] != nil"))
        XCTAssertTrue(block.contains("self.brightnessTransitionTasks[id] != nil"))
        XCTAssertTrue(block.contains("self.restoreTasks[id] != nil"))
        XCTAssertTrue(block.contains("self.overspeedWarningActiveID == id"))
        XCTAssertTrue(block.contains("device.role?.isHeadlightFed == true"))
        XCTAssertTrue(block.contains("!self.headlightPowerSessionActive"))
    }

    func testV9010AnimationTransportRemainsBaseline() throws {
        let monitor = try monitorSource()
        XCTAssertTrue(monitor.contains("protocolPacing=20Hz/rawBLEDIM"))
        XCTAssertFalse(monitor.contains("protocolPacing=Lotus20Hz/BLEDIM10Hz"))
        XCTAssertFalse(monitor.contains("scheduleRobustSteadyStateRecovery"))
        XCTAssertFalse(monitor.contains("rounds=3"))
    }
}

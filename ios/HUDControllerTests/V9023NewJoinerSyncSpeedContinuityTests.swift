import XCTest
@testable import HUDController

final class V9023NewJoinerSyncSpeedContinuityTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testProductionBLEDIMIsAlreadyOnMinimalAndLabUIIsRemoved() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let view = try source("HUDController/UI/AmbientLightingView.swift")
        XCTAssertTrue(monitor.contains("? .alreadyOnMinimal"))
        XCTAssertTrue(monitor.contains("case .alreadyOnMinimal:"))
        XCTAssertTrue(monitor.contains("activeBLEDIMAnimationStrategyByID[id] ?? .alreadyOnMinimal"))
        XCTAssertFalse(view.contains("BLEDIM ANIMATION TEST LAB"))
        XCTAssertTrue(view.contains("BLEDIM PRODUCTION ANIMATION"))
        XCTAssertTrue(view.contains("Already-On Minimal"))
    }

    func testHeadlightBarrierUsesNewJoinersOnly() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private func isJoiningHeadlightTransition"))
        XCTAssertTrue(monitor.contains("return !animatedConnectionSession.contains(id)"))
        XCTAssertTrue(monitor.contains("let joiningDevices = eligibleDevices.filter { isJoiningHeadlightTransition($0) }"))
        XCTAssertTrue(monitor.contains("let alreadyActiveDevices = eligibleDevices.filter { !isJoiningHeadlightTransition($0) }"))
        XCTAssertTrue(monitor.contains("let expected = Set(joiningDevices.map(\\.id))"))
        XCTAssertTrue(monitor.contains("Headlight sync barrier opened NEW-JOINERS-ONLY"))
        XCTAssertTrue(monitor.contains("untouchedAlreadyActive"))
        XCTAssertTrue(monitor.contains("Headlight sync barrier common T0 newJoinersReady="))
        XCTAssertTrue(monitor.contains("self.startSynchronizedBreathSession()"))
    }

    func testAlreadyActiveLightRemainsUntouched() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let view = try source("HUDController/UI/AmbientLightingView.swift")
        XCTAssertTrue(monitor.contains("Never call resetParticipantForHeadlightBarrier on an already-active light"))
        XCTAssertTrue(monitor.contains("for device in joiningDevices where isControllable(device.id)"))
        XCTAssertTrue(view.contains("A light that is already active stays untouched"))
        XCTAssertTrue(view.contains("only Center + Dashboard wait for each other"))
        XCTAssertTrue(view.contains("if all three are still joining, all three synchronize"))
    }

    func testUpgradeSyncMigrationAndSpeedContinuityRemain() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(monitor.contains("HUD.Ambient.v90_22.headlightBarrierSyncMigrated"))
        XCTAssertTrue(monitor.contains("Flight recorder v90.23 enabled"))
        XCTAssertTrue(monitor.contains("syncMembership=newJoinersOnly"))
        XCTAssertTrue(speed.contains("private static func normalizedRoadIdentity"))
        XCTAssertTrue(speed.contains("same-road fast handoff"))
        XCTAssertTrue(speed.contains("same-road untagged continuity"))
        XCTAssertTrue(speed.contains("improvedDisplayContinuityFresh = true"))
        XCTAssertTrue(speed.contains("warning freshness unchanged"))
    }
}

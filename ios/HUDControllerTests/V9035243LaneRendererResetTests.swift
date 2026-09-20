import XCTest
@testable import HUDController

final class V9035243LaneRendererResetTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let thisFile = URL(fileURLWithPath: #filePath)
        let iosRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: iosRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testPhysicalLaneClearRecreatesNavigationRenderer() throws {
        let src = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(src.contains("private var laneRendererResetTask: Task<Void, Never>?"))
        XCTAssertTrue(src.contains("schedulePhysicalLaneRendererResetAfterClear"))
        XCTAssertTrue(src.contains("self.obd.applyNavigationWidgets()"))
        XCTAssertTrue(src.contains("self.navigation.sendCurrent(owner: self.navigation.feedOwner)"))
        XCTAssertTrue(src.contains("Lane renderer reset → final clear"))
        XCTAssertTrue(src.contains("HUD LANE RESET"))
    }

    func testRendererResetIsGenerationGuardedAndCancelledByNewLanes() throws {
        let src = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(src.contains("self.lanePresentationGeneration == generation"))
        XCTAssertTrue(src.contains("self.activeLaneGuidance.isEmpty"))
        XCTAssertTrue(src.contains("laneRendererResetTask?.cancel()"))
        XCTAssertTrue(src.contains("let hadLanePayload = !activeLaneGuidance.isEmpty"))
        XCTAssertTrue(src.contains("guard hadLanePayload, navigation.navigationActive else { return }"))
    }

    func testDualMainVideoWireCompatibilityIsCarriedForward() throws {
        let src = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(src.contains("U2WH2642"))
        XCTAssertTrue(src.contains("U2WH2643"))
    }
}

import XCTest

final class V9034102LaneProbeReconfigureTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let ios = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: ios.appendingPathComponent(relative), encoding: .utf8)
    }

    func testActiveProbeCandidateCanBeReconfiguredWithoutClearingLanes() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(app.contains("laneRightSideProbeWidget: String?"))
        XCTAssertTrue(app.contains("laneRightSideProbeWidget != rightWidget"))
        XCTAssertTrue(app.contains("if laneRightSideProbeActive && !reconfiguring { return }"))
        XCTAssertTrue(app.contains("laneRightSideProbeWidget = rightWidget"))
        XCTAssertTrue(app.contains("reconfiguring ? \"reconfigure\" : \"activate\""))
    }
}

import XCTest
@testable import HUDController

final class V54RemovedSourceExclusionTests: XCTestCase {
    func testProjectExplicitlyExcludesRemovedProbeSources() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let iosRoot = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let projectURL = iosRoot.appendingPathComponent("project.yml")
        let project = try String(contentsOf: projectURL, encoding: .utf8)

        XCTAssertTrue(project.contains("- Media/HudTextRendererProbe.swift"))
        XCTAssertTrue(project.contains("- V41TextRendererProbeTests.swift"))
        XCTAssertTrue(project.contains("- AppStateInitializationOrderTests.swift"))
    }

    func testCurrentSourceTreeDoesNotContainProbeImplementation() {
        let testsURL = URL(fileURLWithPath: #filePath)
        let iosRoot = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let probeURL = iosRoot
            .appendingPathComponent("HUDController/Media/HudTextRendererProbe.swift")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: probeURL.path),
            "HudTextRendererProbe.swift was removed in v53 and must not return"
        )
    }
}

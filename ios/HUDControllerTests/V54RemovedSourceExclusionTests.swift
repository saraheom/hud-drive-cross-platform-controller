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

    func testLegacyProbeFileIsAbsentOrInert() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let iosRoot = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let probeURL = iosRoot
            .appendingPathComponent("HUDController/Media/HudTextRendererProbe.swift")

        // Older Git checkouts may retain previously tracked files when a newer
        // ZIP is copied over them. Physical presence is therefore not itself a
        // failure. If the path exists, it must be only our inert v55 overwrite,
        // and project.yml already excludes it from compilation.
        guard FileManager.default.fileExists(atPath: probeURL.path) else {
            return
        }

        let source = try String(contentsOf: probeURL, encoding: .utf8)

        XCTAssertTrue(source.contains("v55 compatibility shim"))
        XCTAssertFalse(source.contains("final class HudTextRendererProbe"))
        XCTAssertFalse(source.contains("enum HudTextProbeRoute"))
        XCTAssertFalse(source.contains("HudCommands.textNotificationProbe("))
        XCTAssertFalse(source.contains("HudCommands.persistentNavigationTextProbe("))
    }
}

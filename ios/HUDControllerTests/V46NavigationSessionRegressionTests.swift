import XCTest
@testable import HUDController

final class V46NavigationSessionRegressionTests: XCTestCase {
    func testHudSessionResetDoesNotStopCapture() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/ExternalNavigationCapture.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        guard let start = source.range(of: "func hudSessionDidReset(reason: String)") else {
            XCTFail("hudSessionDidReset not found")
            return
        }

        let tail = String(source[start.lowerBound...])
        let methodText = String(tail.prefix(3000))

        XCTAssertFalse(methodText.contains("stop()"))
        XCTAssertFalse(methodText.contains("presentFullDisplayPicker()"))
        XCTAssertTrue(methodText.contains("navigation.sendCurrent()"))
    }
}

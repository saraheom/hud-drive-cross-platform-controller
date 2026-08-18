import XCTest
@testable import HUDController

final class V86UserArmedCapturePolicyTests: XCTestCase {
    func testPhysicalStopIsTheOnlyIntentOffAssignment() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let source = try String(
            contentsOf: root.appendingPathComponent(
                "HUDController/Navigation/ExternalNavigationCapture.swift"
            ),
            encoding: .utf8
        )

        guard let boundary = source.range(of: "#else") else {
            XCTFail("Expected simulator fallback boundary")
            return
        }

        let physical = String(source[..<boundary.lowerBound])
        XCTAssertEqual(
            physical.components(
                separatedBy: "captureDesired = false"
            ).count - 1,
            1
        )

        XCTAssertTrue(
            physical.contains(
                "deactivateNavigation(reason: \"Screen capture manually stopped\")"
            )
        )
        XCTAssertTrue(
            physical.contains(
                "HUD disconnected reason=\\(reason); suspending stream, preserving userArmed=\\(captureDesired)"
            )
        )
    }
}

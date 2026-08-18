import XCTest
@testable import HUDController

final class V85UserArmedCaptureRegressionTests: XCTestCase {
    func testV83TestsDoNotCountDeviceAndSimulatorAssignmentsTogether() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let source = try String(
            contentsOf: root.appendingPathComponent(
                "HUDControllerTests/V83UserArmedCaptureSessionTests.swift"
            ),
            encoding: .utf8
        )

        XCTAssertFalse(
            source.contains(
                #"components(separatedBy: "captureDesired = false")"#
            )
        )
        XCTAssertFalse(source.contains(#""private func apply(""#))
        XCTAssertTrue(source.contains("func stop()"))
        XCTAssertTrue(source.contains("hudTransportDisconnected"))
    }
}

import XCTest
@testable import HUDController

final class V65StaleAppleTestCleanupTests: XCTestCase {
    func testSupersededAppleRegressionFilesAreExplicitlyExcluded() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("project.yml")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("- V59AppleArrowDirectionTests.swift"))
        XCTAssertTrue(source.contains("- V60AppleArrowComponentIsolationTests.swift"))
        XCTAssertTrue(source.contains("- V61AppleComponentRegressionTests.swift"))
        XCTAssertTrue(source.contains("- V62AppleArrowShieldTests.swift"))
    }
}

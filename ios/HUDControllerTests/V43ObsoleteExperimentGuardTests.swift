import XCTest
@testable import HUDController

final class V43ObsoleteExperimentGuardTests: XCTestCase {
    func testNoTestsReferenceRemovedMusicSlotHelper() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()

        let names = [
            "V39NavigationValidationTests.swift",
            "V40MusicWeatherSlotTests.swift"
        ]

        for name in names {
            let url = testsURL.appendingPathComponent(name)
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(source.contains(".isMusicDisplaySlot"))
            XCTAssertFalse(source.contains(#"displayName, "Music""#))
        }
    }
}

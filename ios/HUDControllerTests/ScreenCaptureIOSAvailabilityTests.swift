import XCTest
@testable import HUDController

final class ScreenCaptureIOSAvailabilityTests: XCTestCase {
    func testDeviceImplementationAvoidsMacOnlyScreenCaptureProperties() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/ExternalNavigationCapture.swift")

        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        // These properties exist in ScreenCaptureKit generally but Xcode 27
        // marks them unavailable for iOS.
        let forbiddenAssignments = [
            "config.allowedPickerModes =",
            "config.allowsChangingSelectedContent =",
            "config.excludedBundleIDs =",
            "config.minimumFrameInterval =",
            "config.queueDepth =",
            "config.scalesToFit ="
        ]

        for forbidden in forbiddenAssignments {
            XCTAssertFalse(
                source.contains(forbidden),
                "iOS implementation must not assign macOS-only property: \(forbidden)"
            )
        }

        XCTAssertTrue(source.contains("picker.present()"))
        XCTAssertTrue(source.contains("config.showsMicrophoneControl = false"))
        XCTAssertTrue(source.contains("timeIntervalSince(lastProcessedAt) >= 0.8"))
    }
}

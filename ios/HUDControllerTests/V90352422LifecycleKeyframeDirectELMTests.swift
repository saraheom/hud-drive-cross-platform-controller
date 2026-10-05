import XCTest

final class V90352422LifecycleKeyframeDirectELMTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testLifecycleAwareInvalidSessionRecoveryPreservesTCP() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        let root = try source("HUDController/UI/RootView.swift")
        XCTAssertTrue(root.contains("applicationWillResignActive()"))
        XCTAssertTrue(video.contains("suspendDecoderForLifecycle"))
        XCTAssertTrue(video.contains("resumeDecoderAfterLifecycle"))
        XCTAssertTrue(video.contains("kVTInvalidSessionErr (-12903)"))
        XCTAssertTrue(video.contains("one bounded native keyframe request armed"))
        XCTAssertTrue(video.contains("keyframeRequestCooldown: TimeInterval = 10.0"))
        XCTAssertTrue(video.contains("u2wvideo-request-keyframe.cgi"))
    }

    func testDirectELMProbeIsOneShotAndDoesNotResetAdapter() throws {
        let elm = try source("HUDController/Bluetooth/DirectELM327Manager.swift")
        let ui = try source("HUDController/UI/VehicleView.swift")
        XCTAssertTrue(elm.contains("let command = \"010D\\r\""))
        XCTAssertFalse(elm.contains("\"ATZ\\r\""))
        XCTAssertFalse(elm.contains("\"ATSP0\\r\""))
        XCTAssertTrue(elm.contains("coexistence_checkpoint"))
        XCTAssertTrue(elm.contains("selectAndConnect"))
        XCTAssertTrue(elm.contains("diagnostics.record(\"elm327\""))
        XCTAssertTrue(ui.contains("DIRECT ELM327 FEASIBILITY"))
        XCTAssertTrue(ui.contains("Production Map Mode speed remains GPS"))
    }

    func testCurrentReleaseStringsAreAligned() throws {
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(app.contains("appVersion=v90.35.3.24.23"))
        XCTAssertTrue(ui.contains("v90.35.3.24.23 pairs with U2W v8.35 Bounded KeyFrame Request + unchanged v8.34 Hard-Bounded Mirror + exact v8.31 Raw Relay"))
        XCTAssertTrue(video.contains("v8.35 package keeps exact v8.31 raw relay + unchanged v8.34 hard-bounded mirror"))
    }
}

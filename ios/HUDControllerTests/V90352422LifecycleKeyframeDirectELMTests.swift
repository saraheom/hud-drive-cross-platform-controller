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
        XCTAssertTrue(elm.contains("guard let bytes = \"010D\\r\".data(using: .ascii)"))
        XCTAssertFalse(elm.contains("\"ATZ\\r\""))
        XCTAssertFalse(elm.contains("\"ATSP0\\r\""))
        XCTAssertTrue(elm.contains("event: \"connect_begin\""))
        XCTAssertTrue(elm.contains("event: \"speed_probe_valid\""))
        XCTAssertTrue(elm.contains("hud_obd_before"))
        XCTAssertTrue(elm.contains("hud_obd_after"))
        XCTAssertTrue(elm.contains("selectAndConnect"))
        XCTAssertTrue(elm.contains("diagnostics.record(\"elm327\""))
        XCTAssertTrue(ui.contains("DIRECT ELM327 FEASIBILITY"))
        XCTAssertTrue(ui.contains("Send one 01 0D speed probe"))

        // The parked probe remains one request even though Map Mode now polls.
        let start = try XCTUnwrap(elm.range(of: "func runOneShotVehicleSpeedProbe()"))
        let end = try XCTUnwrap(elm.range(of: "private func sendVehicleSpeedRequest", range: start.upperBound..<elm.endIndex))
        let manualProbe = String(elm[start.lowerBound..<end.lowerBound])
        XCTAssertEqual(manualProbe.components(separatedBy: "sendVehicleSpeedRequest(").count - 1, 1)
        XCTAssertFalse(manualProbe.contains("startPollingIfReady("))
        XCTAssertTrue(manualProbe.contains("guard !speedProbeActive"))
        XCTAssertTrue(manualProbe.contains("event: \"speed_probe_timeout\""))
    }

    func testMapModeUsesDirectOBDWithGPSFallbackAndReturnsHUDOwnership() throws {
        let elm = try source("HUDController/Bluetooth/DirectELM327Manager.swift")
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/UI/VehicleView.swift")
        XCTAssertTrue(elm.contains("guard mapModeOwnershipRequested, gattReady"))
        XCTAssertTrue(elm.contains("Map Mode direct OBD polling START rate=5Hz command=010D only"))
        XCTAssertTrue(elm.contains("milliseconds(200)"))
        XCTAssertTrue(elm.contains("func releaseMapModeOwnership()"))
        XCTAssertTrue(elm.contains("stopPolling(reason: \"Map Mode ended\")"))
        XCTAssertTrue(app.contains("obd.suspendForDirectELMOwnership"))
        XCTAssertTrue(app.contains("directELM.claimForMapMode()"))
        XCTAssertTrue(app.contains("directELM.releaseMapModeOwnership()"))
        XCTAssertTrue(app.contains("obd.resumeAfterDirectELMOwnership"))
        XCTAssertTrue(app.contains("let speed = directELM.freshSpeedMph() ?? gpsSpeed"))
        XCTAssertTrue(ui.contains("Map Mode uses fresh OBD speed • GPS fallback"))
    }

    func testCurrentReleaseStringsAreAligned() throws {
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(app.contains("appVersion=v90.35.3.24.24"))
        XCTAssertTrue(ui.contains("v90.35.3.24.24 pairs with U2W v8.36 Passive Seam Observer + unchanged v8.35 keyframe layer + unchanged v8.34 Hard-Bounded Mirror + exact v8.31 Raw Relay"))
        XCTAssertTrue(video.contains("v8.35 package keeps exact v8.31 raw relay + unchanged v8.34 hard-bounded mirror"))
    }
}

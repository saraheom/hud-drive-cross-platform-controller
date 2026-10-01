import XCTest

final class V90352418RobustMapModeMainVideoTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testFallbackFirstMapModeAndJPEGIngressWatchdog() throws {
        let app = try text("ios/HUDController/App/AppState.swift")
        let relay = try text("ios/HUDController/MapMode/U2WHUDFrameRelayClient.swift")
        XCTAssertTrue(app.contains("physical Map Mode no longer depends on MainVideo readiness"))
        XCTAssertTrue(app.contains("guard firstFrameDelivered else"))
        XCTAssertTrue(app.contains("sourceMapImage: freshLiveMapImage"))
        XCTAssertTrue(relay.contains("case .waiting(let error):"))
        XCTAssertTrue(relay.contains("Task.sleep(for: .seconds(2.5))"))
    }

    func testCodecBadDataKeepsValidatedSPSPPSAndWaitsForIDR() throws {
        let video = try text("ios/HUDController/MapMode/U2WMainVideoClient.swift")
        let sanitizer = try text("ios/HUDController/MapMode/H264MainVideoSanitizer.swift")
        XCTAssertTrue(video.contains("sanitizer.quarantineReferenceChainUntilIDR()"))
        XCTAssertTrue(video.contains("decoder.hardRecoverAwaitingIDR(reason: reason)"))
        XCTAssertTrue(video.contains("validated SPS/PPS PRESERVED; TCP PRESERVED"))
        XCTAssertTrue(sanitizer.contains("func quarantineReferenceChainUntilIDR()"))
    }
}

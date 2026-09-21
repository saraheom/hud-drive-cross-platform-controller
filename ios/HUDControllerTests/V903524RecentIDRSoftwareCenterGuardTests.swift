import XCTest

final class V903524RecentIDRSoftwareCenterGuardTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testRecentIDRRelayIsBoundedAndClosesClientAfterIDRRace() throws {
        let relay = try source("../u2w/v8.24_RecentIDRRelay/source/u2w_mainvideo_relay.c")
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(relay.contains("U2WH2643"))
        XCTAssertTrue(video.contains("U2WH2642"))
        XCTAssertTrue(video.contains("U2WH2643"))
        XCTAssertTrue(video.contains("acceptedMagics"))
        XCTAssertTrue(relay.contains("#define RECENT_CAP (4*1024*1024)"))
        XCTAssertTrue(relay.contains("client-live-bootstrap-recent-idr-anchor"))
        XCTAssertTrue(relay.contains("recent-anchor-cap-exceeded-wait-next-idr"))
    }

    func testSoftwareDecoderAndRecentAnchorRecoveryAreRequested() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder"))
        XCTAssertTrue(video.contains("NSNumber(value: false)"))
        XCTAssertTrue(video.contains("bounded recovery attempt #1"))
        XCTAssertTrue(video.contains("WAITING_FRESH_IDR"))
        XCTAssertTrue(video.contains("TCP PRESERVED, quarantining replay and waiting for next live IDR"))
        XCTAssertTrue(video.contains("Decoder recovery • one bounded recent-IDR reseed"))
    }

    func testCenterOnlyDayGuardDoesNotWaitForDashboard() throws {
        let ambient = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(ambient.contains("centerDayGuardSeconds: TimeInterval = 1.0"))
        XCTAssertTrue(ambient.contains("Center-only DAY guard armed"))
        XCTAssertTrue(ambient.contains("Dashboard not required"))
        XCTAssertFalse(ambient.contains("Dashboard+Center BOTH-OFF stable; fast corroborated DAY commit"))
    }
}

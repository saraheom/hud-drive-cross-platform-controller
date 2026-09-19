import XCTest
@testable import HUDController

final class V903516iPhoneMainVideoFilterTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func hexData(_ hex: String) -> Data {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return Data(bytes)
    }

    func testKnownGoodCarPlayParameterSetsAreAcceptedOnIPhone() {
        let sanitizer = H264MainVideoSanitizer()
        let sps = hexData("2764001fac131450320f69b80868303682211960")
        let pps = hexData("28ee3cb0")

        XCTAssertEqual(sanitizer.process(sps)?.kind.rawValue, "SPS")
        XCTAssertEqual(sanitizer.process(pps)?.kind.rawValue, "PPS")
        XCTAssertEqual(sanitizer.stats.acceptedSPS, 1)
        XCTAssertEqual(sanitizer.stats.acceptedPPS, 1)
        XCTAssertEqual(sanitizer.stats.rejectedNALs, 0)
    }

    func testFalseParameterSetsAndForbiddenBitAreRejected() {
        let sanitizer = H264MainVideoSanitizer()
        XCTAssertNil(sanitizer.process(Data([0xA7, 0x64, 0x00, 0x1F])))
        XCTAssertNil(sanitizer.process(Data([0x27] + Array(repeating: 0x55, count: 4_000))))
        XCTAssertNil(sanitizer.process(hexData("28ee3cb0")), "PPS cannot be accepted before a validated SPS")
        XCTAssertEqual(sanitizer.stats.acceptedNALs, 0)
        XCTAssertEqual(sanitizer.stats.rejectedNALs, 3)
    }

    func testMainVideoUsesContinuousDedicatedTCPAndKeepsIPhoneFiltering() throws {
        let app = try source("HUDController/App/AppState.swift")
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")

        let transportReady = app.components(separatedBy: "bluetooth.onTransportReady =")[1]
            .components(separatedBy: "bluetooth.onHUDSessionReset =")[0]
        XCTAssertTrue(transportReady.contains(#"mainVideo.start(reason: "HUD BLE transport ready — continuous predecode")"#))
        XCTAssertTrue(app.contains(#"mainVideo.start(reason: "live U2W Map Mode relay")"#))
        XCTAssertTrue(app.contains("keep continuous predecode alive"))

        XCTAssertTrue(video.contains("U2WMainVideoTCPWorker"))
        XCTAssertTrue(video.contains("port: 15332"))
        XCTAssertTrue(video.contains("U2WH2642"))
        XCTAssertTrue(video.contains("H264MainVideoSanitizer"))
        XCTAssertTrue(video.contains("CONTINUE without IDR reset"))
        XCTAssertTrue(video.contains("PRESERVE transport/decoder, no reconnect"))
        XCTAssertTrue(video.contains("sourceStaleInterval: TimeInterval = 15.0"))
        XCTAssertTrue(video.contains("u2wvideo-relay-start.cgi"))
        XCTAssertFalse(video.contains("u2wvideo-main-stream.cgi"))
    }

    func testItem10MapModeProbeIsRetired() throws {
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertFalse(ui.contains("Native OBD speed test"))
        XCTAssertTrue(app.contains("suppressCustomSpeedForNativeOBDProbe: false"))
    }
}

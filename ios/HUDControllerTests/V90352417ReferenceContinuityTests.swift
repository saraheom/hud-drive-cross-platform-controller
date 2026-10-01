import XCTest
@testable import HUDController

final class V90352417ReferenceContinuityTests: XCTestCase {
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

    /// These are compact real 800×480 H.264 headers from the field diagnostic.
    /// The test changes only frame_num in a P-slice header; it contains no image
    /// assertions and exists solely to exercise reference-chain continuity.
    func testMissingReferencePictureIsQuarantinedUntilIDR() {
        let sanitizer = H264MainVideoSanitizer()
        let sps = hexData("2764001fac131450320f69b80868303682211960")
        let pps = hexData("28ee3cb0")
        let idr = hexData("25b800400093ffd287a9cdffe11b01f492d6274cb2f5c56913eef000000300000300000300e789ae2cec4a9c5f68000003001040089813e0300097820a07501b009102e00c40000003000003000003000003000003000003000003000003000003000003000003000003000003000404aa55aa553600000006000000f9ffffff2e")
        let pFrame1 = hexData("21e0020012567588ff00e8deef46c34d415236c3a2d25be4533537a071f26bee118775e15002fbb4c5f0aa55aa55ff08000006000000f9fffffff708")
        var pFrame3 = pFrame1
        pFrame3[2] = 0x06 // same validated header/body, frame_num 1 -> 3

        XCTAssertEqual(sanitizer.process(sps)?.kind, .sps)
        XCTAssertEqual(sanitizer.process(pps)?.kind, .pps)
        XCTAssertNil(sanitizer.process(pFrame1), "P-slice must not bootstrap without an IDR")
        XCTAssertEqual(sanitizer.process(idr)?.kind, .idr)
        XCTAssertEqual(sanitizer.process(pFrame1)?.kind, .slice)

        XCTAssertNil(sanitizer.process(pFrame3))
        XCTAssertEqual(sanitizer.stats.frameNumDiscontinuities, 1)
        XCTAssertTrue(sanitizer.stats.waitingForReferenceIDR)
        let reason = sanitizer.takeContinuityBreakReason()
        XCTAssertTrue(reason?.contains("expected=2 actual=3") == true)

        XCTAssertEqual(sanitizer.process(idr)?.kind, .idr)
        XCTAssertFalse(sanitizer.stats.waitingForReferenceIDR)
        XCTAssertEqual(sanitizer.process(pFrame1)?.kind, .slice)
    }
}

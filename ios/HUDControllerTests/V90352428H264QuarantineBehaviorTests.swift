import XCTest
@testable import HUDController

final class V90352428H264QuarantineBehaviorTests: XCTestCase {
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

    private var sps: Data { hexData("2764001fac131450320f69b80868303682211960") }
    private var pps: Data { hexData("28ee3cb0") }
    private var idr: Data {
        hexData("25b800400093ffd287a9cdffe11b01f492d6274cb2f5c56913eef000000300000300000300e789ae2cec4a9c5f68000003001040089813e0300097820a07501b009102e00c40000003000003000003000003000003000003000003000003000003000003000003000003000003000404aa55aa553600000006000000f9ffffff2e")
    }
    private var p1: Data {
        hexData("21e0020012567588ff00e8deef46c34d415236c3a2d25be4533537a071f26bee118775e15002fbb4c5f0aa55aa55ff08000006000000f9fffffff708")
    }

    func testSmallOnePictureLossStillFlowsImmediately() {
        let sanitizer = H264MainVideoSanitizer()
        var p3 = p1
        p3[2] = 0x06

        XCTAssertEqual(sanitizer.processBatch(sps).count, 1)
        XCTAssertEqual(sanitizer.processBatch(pps).count, 1)
        XCTAssertEqual(sanitizer.processBatch(idr).count, 1)
        XCTAssertEqual(sanitizer.processBatch(p1).count, 1)
        XCTAssertEqual(sanitizer.processBatch(p3).count, 1)
        XCTAssertEqual(sanitizer.stats.frameNumDiscontinuities, 1)
        XCTAssertEqual(sanitizer.stats.continuityQuarantineCandidates, 0)
        XCTAssertFalse(sanitizer.stats.waitingForReferenceIDR)
    }

    func testGrossNonReferenceCandidateIsHeldAndDroppedWhenOldCadenceResumes() {
        let sanitizer = H264MainVideoSanitizer()
        var p2 = p1
        p2[2] = 0x04
        var foreign = p1
        foreign[0] = 0x01 // nal_ref_idc=0, type=1: Oct-7 contaminant class
        foreign[2] = 0xC8 // grossly off-cadence frame_num for this compact fixture

        XCTAssertEqual(sanitizer.processBatch(sps).count, 1)
        XCTAssertEqual(sanitizer.processBatch(pps).count, 1)
        XCTAssertEqual(sanitizer.processBatch(idr).count, 1)
        XCTAssertEqual(sanitizer.processBatch(p1).count, 1)

        XCTAssertTrue(sanitizer.processBatch(foreign).isEmpty)
        XCTAssertTrue(sanitizer.takeContinuityQuarantineReason()?.contains("action=HOLD") == true)

        let resumed = sanitizer.processBatch(p2)
        XCTAssertEqual(resumed.count, 1)
        XCTAssertTrue(sanitizer.takeContinuityQuarantineReason()?.contains("old_cadence_resumed") == true)
        XCTAssertEqual(sanitizer.stats.continuityQuarantineRejects, 1)
        XCTAssertFalse(sanitizer.stats.waitingForReferenceIDR)
    }
}

import XCTest
@testable import HUDController

final class HudProtocolFrameTests: XCTestCase {
    func testExtractSingleCompleteFrame() {
        var buffer = Data([0x02, 0x01, 0x02, 0x03])
        let frames = HudProtocol.extractFrames(from: &buffer)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], Data([0x02, 0x01, 0x02, 0x03]))
        XCTAssertTrue(buffer.isEmpty)
    }

    func testExtractLeavesIncompleteFrameBuffered() {
        var buffer = Data([0x02, 0x01, 0x02])
        let frames = HudProtocol.extractFrames(from: &buffer)

        XCTAssertTrue(frames.isEmpty)
        XCTAssertEqual(buffer, Data([0x02, 0x01, 0x02]))
    }

    func testExtractMultipleFrames() {
        var buffer = Data([
            0x02, 0x01, 0x03,
            0x02, 0x02, 0x03
        ])
        let frames = HudProtocol.extractFrames(from: &buffer)

        XCTAssertEqual(frames, [
            Data([0x02, 0x01, 0x03]),
            Data([0x02, 0x02, 0x03])
        ])
        XCTAssertTrue(buffer.isEmpty)
    }
}

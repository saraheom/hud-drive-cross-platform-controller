import XCTest
@testable import HUDController

final class HudProtocolFrameTests: XCTestCase {
    func testExtractSingleCompleteFrame() {
        // Raw STX (0x02) is a frame boundary on the HUD wire protocol, not legal
        // unescaped payload. Use an ordinary payload byte in this baseline test.
        var buffer = Data([0x02, 0x01, 0x04, 0x03])
        let frames = HudProtocol.extractFrames(from: &buffer)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], Data([0x02, 0x01, 0x04, 0x03]))
        XCTAssertTrue(buffer.isEmpty)
    }

    func testExtractLeavesIncompleteFrameBuffered() {
        // Keep a syntactically valid incomplete frame. A trailing raw STX would
        // intentionally resynchronize to that newer STX under the v90.35.3.5 parser.
        var buffer = Data([0x02, 0x01, 0x04])
        let frames = HudProtocol.extractFrames(from: &buffer)

        XCTAssertTrue(frames.isEmpty)
        XCTAssertEqual(buffer, Data([0x02, 0x01, 0x04]))
    }

    func testExtractMultipleFrames() {
        var buffer = Data([
            0x02, 0x01, 0x03,
            0x02, 0x04, 0x03
        ])
        let frames = HudProtocol.extractFrames(from: &buffer)

        XCTAssertEqual(frames, [
            Data([0x02, 0x01, 0x03]),
            Data([0x02, 0x04, 0x03])
        ])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testNestedUnescapedSTXResynchronizesToNewerFrame() {
        // A firmware/version frame was split, then a complete Wi-Fi STA event was
        // emitted before the first frame's continuation. Unescaped STX cannot occur
        // inside a valid HUD frame, so the parser must abandon the interrupted frame
        // and preserve the newer event.
        let interruptedHello = Data([0x02, 0x7D, 0x7E, 0x05, 0x00, 0x00, 0x19, 0x48, 0x55, 0x44])
        let wifiStatus = Data([0x02, 0x7D, 0x7E, 0x06, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x09,
                               0x63, 0x6F, 0x6E, 0x6E, 0x65, 0x63, 0x74, 0x65, 0x64, 0x00, 0x00, 0x03])
        var buffer = interruptedHello
        buffer.append(wifiStatus)
        let frames = HudProtocol.extractFrames(from: &buffer)

        XCTAssertEqual(frames, [wifiStatus])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testEscapedSTXDoesNotTriggerResynchronization() {
        // 0x7D 0x7F is the wire encoding of a literal payload STX (0x02).
        var buffer = Data([0x02, 0x01, 0x7D, 0x7F, 0x03])
        let frames = HudProtocol.extractFrames(from: &buffer)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], Data([0x02, 0x01, 0x7D, 0x7F, 0x03]))
    }
}

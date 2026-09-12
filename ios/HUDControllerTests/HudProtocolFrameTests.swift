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
        var buffer = Data([0x02, 0x01, 0x7D, 0x7F, 0x02, 0x03])
        // 0x7D 0x7F is escaped literal STX; the following raw 0x02 is deliberately
        // another frame start, so construct the valid case without a raw nested STX.
        buffer = Data([0x02, 0x01, 0x7D, 0x7F, 0x03])
        let frames = HudProtocol.extractFrames(from: &buffer)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], Data([0x02, 0x01, 0x7D, 0x7F, 0x03]))
    }

}

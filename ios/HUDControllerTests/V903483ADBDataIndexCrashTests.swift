import XCTest
@testable import HUDController

final class V903483ADBDataIndexCrashTests: XCTestCase {
    func testLittleEndianDecoderUsesOffsetRelativeToDataStartIndex() throws {
        var buffer = Data([0xAA, 0xBB, 0xCC, 0xDD,
                           0x11, 0x22, 0x33, 0x44,
                           0x78, 0x56, 0x34, 0x12,
                           0xEE, 0xFF])

        // Reproduce the ADB SYNC parser's consumed-prefix state. Foundation Data
        // may retain a non-zero startIndex after removeFirst(_:), so absolute
        // subscripting such as data[4..<8] is unsafe here.
        buffer.removeFirst(4)

        XCTAssertEqual(try HUDADBClient.readUInt32LE(buffer, offset: 4), 0x12345678)
    }

    func testLittleEndianDecoderRejectsTruncatedInputInsteadOfTrapping() {
        var buffer = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        buffer.removeFirst(3)
        XCTAssertThrowsError(try HUDADBClient.readUInt32LE(buffer, offset: 0))
    }
}

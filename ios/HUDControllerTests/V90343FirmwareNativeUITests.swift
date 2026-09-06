import XCTest
@testable import HUDController

final class V90343FirmwareNativeUITests: XCTestCase {
    func testNativeLanePacketShapeAndSignedRecommendationEncoding() {
        let packet = HudCommands.laneGuidance([
            .init(type: .straight, recommended: false),
            .init(type: .straightLeft, recommended: true),
            .init(type: .straight, recommended: false),
            .init(type: .right, recommended: false),
        ])

        guard let body = HudProtocol.unescape(packet) else {
            XCTFail("Lane packet failed to unescape")
            return
        }

        XCTAssertEqual(body[0], 2)
        XCTAssertEqual(body[1], 113)
        XCTAssertEqual(body[2], 0)

        func int32(at offset: Int) -> Int32 {
            let u = UInt32(body[offset]) << 24
                | UInt32(body[offset + 1]) << 16
                | UInt32(body[offset + 2]) << 8
                | UInt32(body[offset + 3])
            return Int32(bitPattern: u)
        }

        XCTAssertEqual(int32(at: 3), 4)
        XCTAssertEqual(int32(at: 7), -1)
        XCTAssertEqual(int32(at: 11), 5)
        XCTAssertEqual(int32(at: 15), -1)
        XCTAssertEqual(int32(at: 19), -2)
    }

    func testLaneTypeFirmwareValues() {
        XCTAssertEqual(HudCommands.NativeLaneType.straight.rawValue, 1)
        XCTAssertEqual(HudCommands.NativeLaneType.right.rawValue, 2)
        XCTAssertEqual(HudCommands.NativeLaneType.straightRight.rawValue, 3)
        XCTAssertEqual(HudCommands.NativeLaneType.left.rawValue, 4)
        XCTAssertEqual(HudCommands.NativeLaneType.straightLeft.rawValue, 5)
    }

    func testClearLanePacketUsesZeroCount() {
        guard let body = HudProtocol.unescape(HudCommands.clearLaneGuidance()) else {
            XCTFail("Clear lane packet failed to unescape")
            return
        }
        XCTAssertEqual(body[0], 2)
        XCTAssertEqual(body[1], 113)
        XCTAssertEqual(body[2], 0)
        XCTAssertEqual(Array(body[3..<7]), [0, 0, 0, 0])
    }

    func testMiniMusicUsesExistingFirmwareCommands() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("../HUDController/App/AppState.swift")
                .standardizedFileURL,
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("HudCommands.widgetsMiniState(true)"))
        XCTAssertTrue(source.contains("HudCommands.widgetsMiniState(false)"))
        XCTAssertTrue(source.contains("HudCommands.musicNotification("))
        XCTAssertFalse(source.contains("adb "))
    }
}

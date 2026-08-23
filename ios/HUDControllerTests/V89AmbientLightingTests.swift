import XCTest
@testable import HUDController

final class V89AmbientLightingTests: XCTestCase {
    func testRecoveredLotusLanternPackets() {
        XCTAssertEqual(
            Array(LotusLanternProtocol.power(true)),
            [0x7E, 0x04, 0x04, 0x01, 0x00, 0x01, 0xFF, 0x00, 0xEF]
        )
        XCTAssertEqual(
            Array(LotusLanternProtocol.power(false)),
            [0x7E, 0x04, 0x04, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xEF]
        )
        XCTAssertEqual(
            Array(LotusLanternProtocol.color(AmbientRGB(red: 0x12, green: 0x34, blue: 0x56))),
            [0x7E, 0x07, 0x05, 0x03, 0x12, 0x34, 0x56, 0x10, 0xEF]
        )
        XCTAssertEqual(
            Array(LotusLanternProtocol.brightness(50)),
            [0x7E, 0x04, 0x01, 0x32, 0xFF, 0xFF, 0xFF, 0x00, 0xEF]
        )
    }

    func testAmbientControllerKeepsLegacyReliabilityGuards() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/AmbientLightMonitor.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Started BLE advertisement scan for BLEDOM"))
        XCTAssertTrue(source.contains("CBCentralManagerOptionRestoreIdentifierKey"))
        XCTAssertTrue(source.contains("Persistent connection stuck >6s"))
        XCTAssertTrue(source.contains("Ambient watchdog reassert"))
        XCTAssertTrue(source.contains("absenceConfirmationWindows = 3"))
    }

    func testBLEDIM2ExperimentalCB01PacketsAndFFF1Path() throws {
        XCTAssertEqual(
            Array(BLEDIM2Protocol.power(true)),
            [0x7E, 0xFF, 0x04, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF]
        )
        XCTAssertEqual(
            Array(BLEDIM2Protocol.power(false)),
            [0x7E, 0xFF, 0x04, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF]
        )
        XCTAssertEqual(
            Array(BLEDIM2Protocol.color(AmbientRGB(red: 0x12, green: 0x34, blue: 0x56))),
            [0x7E, 0xFF, 0x05, 0x03, 0x12, 0x34, 0x56, 0xFF, 0xEF]
        )
        XCTAssertEqual(
            Array(BLEDIM2Protocol.brightness(50)),
            [0x7E, 0xFF, 0x01, 0x32, 0x00, 0xFF, 0xFF, 0xFF, 0xEF]
        )

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/AmbientLightMonitor.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("BLEDIM2 FFF0/FFF1 experimental"))
        XCTAssertTrue(source.contains("isBLEDIMWriteCharacteristic"))
        XCTAssertTrue(source.contains("EXPERIMENTAL CB01"))
    }
}

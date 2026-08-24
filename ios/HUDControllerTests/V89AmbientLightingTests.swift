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

    func testBLEDIM2FFF1TransportRemainsButGuessedPacketsAreBlocked() throws {
        XCTAssertEqual(BLEDIM2Protocol.serviceUUID, "0000FFF0-0000-1000-8000-00805F9B34FB")
        XCTAssertEqual(BLEDIM2Protocol.writeCharacteristicUUID, "0000FFF1-0000-1000-8000-00805F9B34FB")

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/AmbientLightMonitor.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("BLEDIM2 FFF0/FFF1 raw transport ready"))
        XCTAssertTrue(source.contains("isBLEDIMWriteCharacteristic"))
        XCTAssertTrue(source.contains("BLEDIM write blocked until FFF1 payload is captured"))
        XCTAssertTrue(source.contains("sendRawBLEDIMHex"))
        XCTAssertFalse(source.contains("EXPERIMENTAL CB01"))
    }
}

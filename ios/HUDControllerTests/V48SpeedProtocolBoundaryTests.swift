import XCTest
@testable import HUDController

final class V48SpeedProtocolBoundaryTests: XCTestCase {
    func testFortyFiveMphProducesApproximatelySeventyTwoKmhProtocolValue() {
        let mph = 45.0
        let metersPerSecond = mph / 2.2369362920544
        let protocolKmh = Int((metersPerSecond * 3.6).rounded())

        XCTAssertEqual(protocolKmh, 72)
    }

    func testHUDStillUsesMphSetting() {
        let packet = HudCommands.unitSettings(mph: true, fahrenheit: true)
        guard let body = HudProtocol.unescape(packet) else {
            XCTFail("Could not decode unit settings packet")
            return
        }

        XCTAssertEqual(body[0], 2)
        XCTAssertEqual(body[1], 108)
        XCTAssertEqual(body[2], 0)
    }
}

import XCTest
@testable import HUDController

final class V903416TimeWeatherColdOffSpeedGaugeProbeTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testRecoveredSpeedGaugePacketsEncodeAsKivicSDKDefines() {
        // p2=0x03 is the UART ETX sentinel and must therefore be escaped
        // by HudProtocol.frame as 0x7D, (0x03 ^ 0x7D)=0x7E.
        XCTAssertEqual(
            HudProtocol.hex(HudCommands.speedInformationVisible(true)),
            "02 7D 7F 09 7D 7E 01 03"
        )
        XCTAssertEqual(
            HudProtocol.unescape(HudCommands.speedInformationVisible(true)),
            Data([0x02, 0x09, 0x03, 0x01])
        )
        XCTAssertEqual(
            HudProtocol.hex(HudCommands.speedGaugeEnabled(true)),
            "02 7D 7F 09 0C 01 03"
        )
        XCTAssertEqual(
            HudProtocol.hex(HudCommands.speedGaugeEnabled(false)),
            "02 7D 7F 09 0C 00 03"
        )
    }

    func testExpandedD0D3ProbeAndStockFreerideArePresent() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        let ui = try source("HUDController/UI/VehicleView.swift")
        XCTAssertTrue(speed.contains("runSpeedGaugeZeroProbe"))
        XCTAssertTrue(speed.contains("runSpeedGaugeStockChainProbe"))
        XCTAssertTrue(speed.contains("runSpeedGaugeEdgeProbe"))
        XCTAssertTrue(speed.contains("runStockFreerideGaugeEdgeProbe"))
        XCTAssertTrue(speed.contains("Speedo\", center: \"Simple\", right: \"Weather"))
        XCTAssertTrue(ui.contains("D0 — Gauge ON + zero threshold"))
        XCTAssertTrue(ui.contains("D3 — Exact stock Freeride + gauge edge (parked)"))
        XCTAssertTrue(ui.contains("Restore current HUD"))
    }

    func testColdOffSynchronizationUsesOneOnOffEdgeAfterFinalRehydration() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(app.contains("scheduleTimeWeatherColdOffSynchronization"))
        XCTAssertTrue(app.contains("Task.sleep(for: .milliseconds(650))"))
        XCTAssertTrue(app.contains("Cold-session time/weather sync edge -> transient ON"))
        XCTAssertTrue(app.contains("Task.sleep(for: .milliseconds(350))"))
        XCTAssertTrue(app.contains("Cold-session time/weather sync edge -> authoritative OFF"))
        XCTAssertTrue(app.contains("persisted setting remains OFF"))
    }
}

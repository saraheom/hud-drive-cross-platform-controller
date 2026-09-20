import XCTest
@testable import HUDController

final class V903522LiveIDRLaneAmbientTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testLiveIDRTransportHasBoundedParkedPreflight() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("U2WH2642"))
        XCTAssertTrue(video.contains("U2WH2643"))
        XCTAssertTrue(video.contains("WAITING_LIVE_IDR"))
        XCTAssertTrue(video.contains("bounded recent-IDR bootstrap enabled"))
        XCTAssertTrue(video.contains("relay confirmed RUNNING before TCP open"))
        XCTAssertTrue(video.contains("TCP WAITING deadline expired"))
        XCTAssertTrue(video.contains("MAINVIDEO PREFLIGHT"))
        XCTAssertTrue(video.contains("recent IDR anchor"))
        XCTAssertTrue(video.contains("receiveExactly"))
    }

    func testDecoderRebuildWaitsForFutureIDRAndExposesState() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(video.contains("rebuildAtNextIDR"))
        XCTAssertTrue(video.contains("Decoder rebuild ARMED"))
        XCTAssertTrue(video.contains("existing session preserved until future IDR"))
        XCTAssertTrue(video.contains("Fresh IDR arrived with rebuild armed; atomically rebuilding decoder now"))
        XCTAssertTrue(video.contains("decoderSummary"))
        XCTAssertTrue(ui.contains("VideoToolbox decoder"))
    }

    func testLaneHeadAndBodyLengthAreIndependent() throws {
        let settings = try source("HUDController/Models/HudMapModeSettings.swift")
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(settings.contains("laneArrowHeadScale"))
        XCTAssertTrue(settings.contains("laneArrowBodyLength"))
        XCTAssertTrue(canvas.contains("headScale: CGFloat(settings.laneArrowHeadScale)"))
        XCTAssertTrue(canvas.contains("bodyLength: CGFloat(settings.laneArrowBodyLength)"))
        XCTAssertTrue(ui.contains("Lane arrow head size"))
        XCTAssertTrue(ui.contains("Lane arrow body length"))
    }

    func testCustomizationUsesDemoAndAmbientDisconnectDoesNotForceDay() throws {
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        let ambient = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(ui.contains("snapshot: .customizationDemo"))
        XCTAssertTrue(ui.contains("Demo • not live HUD output"))
        XCTAssertTrue(ambient.contains("Center BLE transport disconnected; preserving NIGHT briefly while Center-only"))
        XCTAssertTrue(ambient.contains("Center-only DAY guard armed"))
        let disconnect = ambient.components(separatedBy: "didDisconnectPeripheral peripheral: CBPeripheral")[1]
            .components(separatedBy: "// MARK: - CBPeripheralDelegate")[0]
        XCTAssertFalse(disconnect.contains(#"markAbsent(reason: "persistent BLE disconnect")"#))
    }
}

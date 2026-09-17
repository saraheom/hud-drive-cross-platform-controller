import XCTest

final class V903517OBDNetworkLaneTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let ios = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: ios.appendingPathComponent(relative), encoding: .utf8)
    }

    func testPersistentItem10ProbeIsSeparateFromCustomizationDisclosure() throws {
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(ui.contains("Native OBD speed test"))
        XCTAssertTrue(ui.contains("setHUDU2WNativeOBDSpeedProbeEnabled"))
        XCTAssertTrue(app.contains("hudU2WNativeOBDProbeEnabled"))
        XCTAssertTrue(app.contains("remains active until toggle off"))
        XCTAssertFalse(app.contains("12s two-phase probe complete"))

        let disclosureStart = try XCTUnwrap(ui.range(of: "DisclosureGroup(isExpanded: $showMapCustomization)"))
        let disclosureTail = ui[disclosureStart.lowerBound...]
        let disclosureEnd = try XCTUnwrap(disclosureTail.range(of: "} label: {"))
        let customizationBody = disclosureTail[..<disclosureEnd.lowerBound]
        XCTAssertFalse(customizationBody.contains("obdProbeControls"))
    }

    func testNetworkTraceCoversDefaultWiFiAndCellular() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("import Network"))
        XCTAssertTrue(video.contains("NWPathMonitor(requiredInterfaceType: .wifi)"))
        XCTAssertTrue(video.contains("NWPathMonitor(requiredInterfaceType: .cellular)"))
        XCTAssertTrue(video.contains("IPHONE NETWORK"))
        XCTAssertTrue(video.contains("15s MainVideo heartbeat"))
    }

    func testSpeedLimitSlotAndLaneWindowing() throws {
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        XCTAssertTrue(canvas.contains("settings.showSpeedLimit && snapshot.speedLimitMph > 0"))
        XCTAssertTrue(canvas.contains("No OSM speed limit = no white rectangle"))
        XCTAssertTrue(canvas.contains("private var displayedLaneValues"))
        XCTAssertTrue(canvas.contains("guard values.count > 4 else { return values }"))
        XCTAssertTrue(canvas.contains("activeInside"))
        XCTAssertTrue(canvas.contains("straight OR right"))
        XCTAssertTrue(canvas.contains("straight OR left"))
        XCTAssertFalse(canvas.contains("return \"arrow.up.right\""))
        XCTAssertFalse(canvas.contains("return \"arrow.up.left\""))
    }
}

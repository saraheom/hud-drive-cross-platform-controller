import XCTest

final class V90352423PreflightLaneETAOBDOwnershipTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testV835StatusMarkersCanSatisfyMainVideoPreflight() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("let v835Marker = fields[\"v835_marker\"] ?? \"?\""))
        XCTAssertTrue(video.contains("let v834MirrorMarker = fields[\"v834_mirror_marker\"] ?? \"?\""))
        XCTAssertTrue(video.contains("legacyMarker == \"YES\" || v835Marker == \"YES\" || v834MirrorMarker == \"YES\""))
        XCTAssertTrue(video.contains("process == \"RUNNING\" && compatibleMarker && supportedRelay"))
    }

    func testLaneRendererResetHasGenerationGuardedLateClear() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(app.contains("Winding Wy field case"))
        XCTAssertTrue(app.contains("Lane renderer reset → guarded settle clear"))
        XCTAssertTrue(app.contains("milliseconds(450)"))
        XCTAssertTrue(app.contains("self.lanePresentationGeneration == generation"))
        XCTAssertTrue(app.contains("self.activeLaneGuidance.isEmpty"))
    }

    func testMapModeETAAMPMCanBeHiddenWithoutChangingRouteETA() throws {
        let settings = try source("HUDController/Models/HudMapModeSettings.swift")
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(settings.contains("var showETAAMPM: Bool"))
        XCTAssertTrue(settings.contains("showETAAMPM = bool(\"HUD.MapMode.showETAAMPM\", default: true)"))
        XCTAssertTrue(ui.contains("Toggle(\"Show AM/PM in ETA\""))
        XCTAssertTrue(canvas.contains("etaDisplayText(snapshot.etaText)"))
    }

    func testHUDOBDOwnershipControlsAreExplicitAndLogged() throws {
        let vehicle = try source("HUDController/UI/VehicleView.swift")
        let obd = try source("HUDController/Vehicle/HudOBDController.swift")
        XCTAssertTrue(vehicle.contains("Connect via HUD"))
        XCTAssertTrue(vehicle.contains("Disconnect HUD OBD"))
        XCTAssertTrue(vehicle.contains("HUD owns OBD"))
        XCTAssertTrue(obd.contains("OBD OWNERSHIP"))
        XCTAssertTrue(obd.contains("manual HUD disconnect request"))
    }
}

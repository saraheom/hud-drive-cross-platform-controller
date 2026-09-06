import XCTest
@testable import HUDController

final class V90348BootAnimationMaintenanceTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testBootAnimationBuilderMatchesPhysicalHUDFormat() {
        XCTAssertEqual(BootAnimationBuilder.width, 480)
        XCTAssertEqual(BootAnimationBuilder.height, 240)
        XCTAssertEqual(BootAnimationBuilder.fps, 24)
        XCTAssertEqual(BootAnimationBuilder.maximumDuration, 12.0)
    }

    func testMaintenanceUsesOnlyDataLocalOverrideAndAtomicPendingCommit() throws {
        let maintenance = try source("HUDController/Firmware/HudMaintenanceManager.swift")
        XCTAssertTrue(maintenance.contains("/data/local/bootanimation/bootanimation.zip"))
        XCTAssertTrue(maintenance.contains("bootanimation.zip.pending"))
        XCTAssertTrue(maintenance.contains("adb.hashRemoteFile(Self.remotePending)"))
        XCTAssertTrue(maintenance.contains("mv \\(Self.remotePending) \\(Self.remoteOverride)"))
        XCTAssertFalse(maintenance.contains("remount"))
        XCTAssertFalse(maintenance.contains("/system/media/bootanimation.zip"))
    }

    func testFailedForceEnablePinExperimentIsNotReachable() throws {
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/AmbientTest/HudNavigationViewIOS26.swift")
        XCTAssertFalse(app.contains("returnHUDRendererKeepingWiFi"))
        XCTAssertFalse(app.contains("hudHotspotBaseband(is5G: true, forceEnable: true)"))
        XCTAssertFalse(ui.contains("Pin AP + Return HUD Mode 4"))
        XCTAssertTrue(ui.contains("Start Firmware Maintenance"))
    }
}

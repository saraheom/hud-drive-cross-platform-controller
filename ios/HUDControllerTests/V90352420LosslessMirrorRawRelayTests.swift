import XCTest

final class V90352420LosslessMirrorRawRelayTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testV2420PairsWithLosslessMirrorAndExactV831RawRelay() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")

        XCTAssertTrue(video.contains("v8.34-hard-bounded-mirror-v831-raw-tcp-15332"))
        XCTAssertTrue(video.contains("U2WH2648"))
        XCTAssertTrue(video.contains("exact v8.31 raw relay"))
        XCTAssertTrue(video.contains("lossless/atomic"))
        XCTAssertTrue(app.contains("appVersion=v90.35.3.24.29"))
        // Pairing metadata remains in diagnostics/AppState instead of a long visible UI banner.
        XCTAssertTrue(app.contains("paired_u2w=v8.38 Read-Only Startup Bootstrap + v8.37 Forensic Seam Capture + unchanged v8.35 helper (injection deferred) + unchanged v8.34 Hard-Bounded Mirror + exact v8.31 Raw Relay"))
        XCTAssertFalse(ui.contains("pairs with U2W v8.38"))
    }

    func testPhysicalMapModeStillKeepsFallbackDuringMainVideoOutage() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(app.contains("KEEPING physical mode 6 + JPEG relay active"))
        XCTAssertTrue(app.contains("physical Map Mode no longer depends on MainVideo readiness"))
    }
}

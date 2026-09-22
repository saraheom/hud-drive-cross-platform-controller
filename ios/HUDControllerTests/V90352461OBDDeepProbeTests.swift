import Foundation
import XCTest
@testable import HUDController

final class V90352461OBDDeepProbeTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testDeepProbeUsesInMemoryRegressionWithoutDirectOBDConnection() throws {
        let bluetooth = try source("ios/HUDController/Bluetooth/HudBluetoothManager.swift")
        let analyzer = try source("ios/HUDController/Vehicle/OBDDeepSpeedAnalyzer.swift")
        XCTAssertTrue(bluetooth.contains("obdDeepSpeedSampleCap = 12_000"))
        XCTAssertTrue(bluetooth.contains("no direct OBD connection / no raw PID request"))
        XCTAssertTrue(analyzer.contains("lagTenths = [-20, -10, -5, 0, 5, 10, 20]"))
        XCTAssertTrue(analyzer.contains("rSquared"))
        XCTAssertTrue(analyzer.contains("bytes[i] == 0x41 && bytes[i + 1] == 0x0D"))
    }

    func testRoadControlKeepsGPSMapSpeedAndUsesHiddenItem10Stimulus() throws {
        let app = try source("ios/HUDController/App/AppState.swift")
        let ui = try source("ios/HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(app.contains("startHUDOBDDeepSpeedProbeV3"))
        XCTAssertTrue(app.contains("GPS Map Mode speed remains unchanged"))
        XCTAssertTrue(app.contains("for attempt in 1...30"))
        XCTAssertTrue(ui.contains("Run 90 s OBD deep probe v3"))
        XCTAssertTrue(ui.contains("Share OBD speed probe v3 report"))
    }

    func testRegressionFindsSyntheticKmhSpeedAndDirectPID410D() {
        var samples: [OBDDeepSpeedSample] = []
        var gps: [OBDDeepGPSPoint] = []
        let base = 1_000.0
        for index in 0..<30 {
            let mph = 10 + index
            let kmh = Int((Double(mph) * 1.609344).rounded())
            let time = base + Double(index)
            gps.append(OBDDeepGPSPoint(time: time, mph: mph))
            samples.append(OBDDeepSpeedSample(
                time: time,
                command: 3,
                p1: 42,
                p2: 7,
                payload: Data([0x99, UInt8(kmh), 0x55])
            ))
        }

        let candidates = OBDDeepSpeedAnalyzer.analyze(samples: samples, gps: gps)
        let direct = candidates.first {
            $0.scalar == "u8" && $0.offset == 1 && abs($0.lagSeconds) < 0.01
        }
        XCTAssertNotNil(direct)
        XCTAssertGreaterThan(direct?.rSquared ?? 0, 0.99)
        XCTAssertEqual(direct?.slopeToMph ?? 0, 0.621, accuracy: 0.05)

        let pidSamples = [OBDDeepSpeedSample(
            time: base,
            command: 3,
            p1: 7,
            p2: 9,
            payload: Data([0x41, 0x0D, 0x3C])
        )]
        let hits = OBDDeepSpeedAnalyzer.directPIDHits(
            samples: pidSamples,
            gps: [OBDDeepGPSPoint(time: base, mph: 37)]
        )
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.rawKmh, 60)
    }
}

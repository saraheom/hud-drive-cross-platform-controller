import XCTest
@testable import HUDController

final class V90344RecordedCarPlayLaneReplayTests: XCTestCase {
    func testRecordedLaneAngleNormalizationCoversNativeFiveShapeVocabulary() {
        XCTAssertEqual(RecordedCarPlayLaneReplay.Lane(angles: [0], recommended: false).nativeType, .straight)
        XCTAssertEqual(RecordedCarPlayLaneReplay.Lane(angles: [45], recommended: false).nativeType, .right)
        XCTAssertEqual(RecordedCarPlayLaneReplay.Lane(angles: [0, 90], recommended: false).nativeType, .straightRight)
        XCTAssertEqual(RecordedCarPlayLaneReplay.Lane(angles: [-45], recommended: false).nativeType, .left)
        XCTAssertEqual(RecordedCarPlayLaneReplay.Lane(angles: [-45, 0], recommended: false).nativeType, .straightLeft)
    }

    func testApplePhysicalCaptureRepresentativeValues() {
        let steps = RecordedCarPlayLaneReplay.Route.appleMaps.steps
        XCTAssertEqual(steps.count, 7)

        XCTAssertEqual(steps[0].captureRecord, 170)
        XCTAssertEqual(steps[0].hudValues, [-5, 1, -1, -1])
        XCTAssertEqual(steps[1].hudValues, [-4, 4, -2, -2])
        XCTAssertEqual(steps[2].hudValues, [-1, -1, 2])
        XCTAssertEqual(steps[5].hudValues, [5, -1])
        XCTAssertEqual(steps[6].captureRecord, 278)
        XCTAssertEqual(steps[6].hudValues, [-4, -5, 1, -2])
    }

    func testGooglePhysicalCaptureRepresentativeValues() {
        let steps = RecordedCarPlayLaneReplay.Route.googleMaps.steps
        XCTAssertEqual(steps.count, 7)

        XCTAssertEqual(steps[0].captureRecord, 115)
        XCTAssertEqual(steps[0].hudValues, [4, -1])
        XCTAssertEqual(steps[1].hudValues, [4, -1, -1, -1])
        XCTAssertEqual(steps[2].hudValues, [4, -3])
        XCTAssertEqual(steps[3].hudValues, [5, -2])
        XCTAssertEqual(steps[4].captureRecord, 132)
    }

    func testReplayRemainsBLEOnlyDiagnostic() throws {
        let appStateURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../HUDController/App/AppState.swift")
            .standardizedFileURL
        let source = try String(contentsOf: appStateURL, encoding: .utf8)

        XCTAssertTrue(source.contains("sendRecordedCarPlayLaneReplayStep"))
        XCTAssertTrue(source.contains("HudCommands.laneGuidance(step.nativeLanes)"))
        XCTAssertTrue(source.contains("navigation.send(step.instruction)"))
        XCTAssertFalse(source.lowercased().contains("adb push"))
        XCTAssertFalse(source.lowercased().contains("remount"))
    }
}

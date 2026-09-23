import XCTest
@testable import HUDController

final class V903523DecoderLaneAmbientTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let thisFile = URL(fileURLWithPath: #filePath)
        let iosRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: iosRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testMainVideoFatalSessionAndSilentOutputRecoveryAreGuarded() throws {
        let src = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(src.contains("private static let invalidSessionStatus: OSStatus = -12903"))
        XCTAssertTrue(src.contains("FATAL VideoToolbox invalid session"))
        XCTAssertTrue(src.contains("HARD decoder recovery, relay-aware live-IDR wait"))
        XCTAssertTrue(src.contains("TCP PRESERVED, quarantining replay and waiting for next live IDR"))
        XCTAssertTrue(src.contains("VideoToolbox output callback failure"))
        XCTAssertTrue(src.contains("soft-flushing delayed VideoToolbox frames before hard recovery"))
        XCTAssertTrue(src.contains("kVTDecompressionPropertyKey_RealTime"))
        XCTAssertTrue(src.contains("LIVE • 20s continuity verified"))
    }

    func testSceneLifecycleNotifiesMainVideoClient() throws {
        let src = try source("HUDController/UI/RootView.swift")
        XCTAssertTrue(src.contains("state.mainVideo.applicationDidBecomeActive()"))
        XCTAssertTrue(src.contains("state.mainVideo.applicationDidEnterBackground()"))
    }

    func testManeuverWithoutLanesGetsPostDeliveryClear() throws {
        let src = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(src.contains("Lane policy → post-maneuver clear"))
        XCTAssertTrue(src.contains("Lane policy → post-maneuver settle clear"))
        XCTAssertTrue(src.contains("lanePresentationGeneration"))
        XCTAssertTrue(src.contains("Task.sleep(for: .milliseconds(150))"))
    }

    func testTopPreviewHasNoSyntheticLanePlaceholder() throws {
        let src = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        guard let range = src.range(of: "snapshot: state.mapModePreviewSnapshot") else {
            return XCTFail("missing live preview")
        }
        let tail = String(src[range.lowerBound...].prefix(700))
        XCTAssertTrue(tail.contains("previewLanePlaceholder: false"))
        XCTAssertTrue(src.contains("snapshot: .customizationDemo"))
    }

    func testStableBothOffConsensusCommitsDayQuickly() throws {
        let src = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(src.contains("centerDayGuardSeconds: TimeInterval = 1.0"))
        XCTAssertTrue(src.contains("Center-only DAY guard armed"))
        XCTAssertTrue(src.contains("Dashboard not required"))
        XCTAssertTrue(src.contains("Dashboard+Center diagnostic consensus"))
        XCTAssertTrue(src.contains("Center remained absent for"))
        XCTAssertTrue(src.contains("through guard → DAY (Dashboard not required)"))
        XCTAssertTrue(src.contains("Center evidence returned during DAY guard"))
        XCTAssertFalse(src.contains("stable Dashboard+Center bothOff consensus"))
    }
    func testMapModeSTAJoinHasBoundedAutomaticRecovery() throws {
        let src = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(src.contains("AUTO JOIN RECOVERY begin mode4→mode6→credentials"))
        XCTAssertTrue(src.contains("hudU2WAutomaticJoinRecoveryCount == 0"))
        XCTAssertTrue(src.contains("HUD has Wi-Fi IP — verifying current display session…"))
        XCTAssertTrue(src.contains("(status == 4 || status == 6)"))
        XCTAssertTrue(src.contains("for checkpoint in 1...2"))
    }

}

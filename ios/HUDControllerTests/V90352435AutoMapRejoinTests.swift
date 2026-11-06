import XCTest
@testable import HUDController

final class V90352435AutoMapRejoinTests: XCTestCase {
    private func permitted(_ overrides: [String: Bool] = [:], time: Double = 40,
                           elapsed: Double = 60, misses: Int = 3, retries: Int = 0) -> Bool {
        func setting(_ key: String, _ defaultValue: Bool) -> Bool { overrides[key] ?? defaultValue }
        return HUDMapModeAutoRejoinPolicy.shouldRetry(
            desiredModeEnabled: setting("auto", true),
            bleConnected: setting("ble", true),
            relayActive: setting("relay", true),
            sessionStatusAvailable: setting("known", true),
            currentViewerReady: setting("ready", false),
            starterBusy: setting("starting", false),
            recoveryBusy: setting("recovering", false),
            healthRecoveryExhausted: setting("exhausted", false),
            secondsSinceRelayStarted: time,
            secondsSincePreviousRetry: elapsed,
            consecutiveMissingViewerChecks: misses,
            attemptedRetries: retries
        )
    }

    func testAfterGasStationRestartMissingViewerCanRejoin() {
        XCTAssertTrue(permitted())
    }
    func testHealthyCurrentViewerNeverRejoins() {
        XCTAssertFalse(permitted(["ready": true]))
    }
    func testUnknownCGIResponseDoesNotCountAsLostViewer() {
        XCTAssertFalse(permitted(["known": false]))
    }
    func testGracePeriodAndConsecutiveProofRequired() {
        XCTAssertFalse(permitted(time: 10))
        XCTAssertFalse(permitted(misses: 1))
    }
    func testCooldownAndSessionBudgetPreventModeChurn() {
        XCTAssertFalse(permitted(elapsed: 8))
        XCTAssertFalse(permitted(retries: HUDMapModeAutoRejoinPolicy.maximumAttemptsPerBLESession))
        XCTAssertFalse(permitted(["recovering": true]))
        XCTAssertFalse(permitted(["exhausted": true]))
    }
    func testAutoOffOrNoBLEProhibitsRecovery() {
        XCTAssertFalse(permitted(["auto": false]))
        XCTAssertFalse(permitted(["ble": false]))
        XCTAssertFalse(permitted(["relay": false]))
        XCTAssertFalse(permitted(["starting": true]))
    }
}

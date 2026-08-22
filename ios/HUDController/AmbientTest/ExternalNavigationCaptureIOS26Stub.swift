#if AMBIENT_IOS26_TEST
import Foundation
import Observation
import UIKit

// Temporary Xcode 26 / ambient-light TestFlight build.
// The real iOS 27 ScreenCaptureKit implementation is intentionally excluded
// from this target.  This API-compatible stub keeps AppState/RootView source
// compatible without importing or linking the iOS 27 capture framework.
@available(iOS 27.0, *)
@MainActor
@Observable
final class ExternalNavigationCapture: NSObject {
    private(set) var status = "Disabled in iOS 26 Ambient Test build"
    private(set) var latestRawText = ""
    private(set) var latestInstruction = NavigationInstruction(
        maneuver: .straight,
        distanceMeters: 0,
        primaryText: "Screen capture disabled",
        streetName: ""
    )
    private(set) var lastFrameAt: Date?
    private(set) var frameCount = 0
    private(set) var validNavigationFrames = 0
    private(set) var rejectedFrames = 0
    private(set) var navigationModeArmed = false
    private(set) var needsUserReselection = false
    private(set) var detectedSource = ExternalNavigationSource.unknown
    private(set) var detectedScreenState = ExternalNavigationScreenState.unknown

    var autoSendToHUD = false
    var keepScreenAwake = false
    var autoRecoverAfterInterruption = false
    var autoEnableNavigationMode = false
    private(set) var captureDesired = false

    private let logger: LogManager

    init(logger: LogManager, navigation: HudNavigationController) {
        self.logger = logger
        super.init()
        logger.log("SCREEN CAPTURE", "Disabled by AMBIENT_IOS26_TEST build flavor")
    }

    func presentFullDisplayPicker() {
        status = "Disabled in iOS 26 Ambient Test build"
        logger.log("SCREEN CAPTURE", "Ignored picker request in ambient-only build")
    }

    func stop() { status = "Disabled in iOS 26 Ambient Test build" }
    func appBecameActive() { }
    func requestAutomaticStartIfDesired() { }
    func hudSessionDidReset(reason: String) { }
    func hudTransportReady(reason: String) { }
    func hudTransportDisconnected(reason: String) { }

    func analyzePhoto(_ image: UIImage) async {
        status = "Saved-screenshot OCR disabled in ambient-only build"
        logger.log("SCREEN CAPTURE", "Ignored saved screenshot in ambient-only build")
    }
}
#endif

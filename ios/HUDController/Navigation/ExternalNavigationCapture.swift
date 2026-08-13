import Foundation
import Observation
import UIKit
import Vision
import CoreMedia
import CoreVideo


#if canImport(ScreenCaptureKit) && !targetEnvironment(simulator)
import ScreenCaptureKit

@available(iOS 27.0, *)
@MainActor
@Observable
final class ExternalNavigationCapture: NSObject {
    private(set) var status = "Stopped"
    private(set) var latestRawText = ""
    private(set) var latestInstruction = NavigationInstruction(
        maneuver: .straight, distanceMeters: 0, primaryText: "Waiting for capture", streetName: ""
    )
    private(set) var lastFrameAt: Date?
    private(set) var frameCount = 0
    private(set) var validNavigationFrames = 0
    private(set) var rejectedFrames = 0
    private(set) var navigationModeArmed = false

    var autoSendToHUD: Bool {
        didSet { UserDefaults.standard.set(autoSendToHUD, forKey: "HUD.Capture.autoSend") }
    }
    var keepScreenAwake: Bool {
        didSet {
            UserDefaults.standard.set(keepScreenAwake, forKey: "HUD.Capture.keepAwake")
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake && stream != nil
        }
    }
    var autoRecoverAfterInterruption: Bool {
        didSet { UserDefaults.standard.set(autoRecoverAfterInterruption, forKey: "HUD.Capture.autoRecover") }
    }
    var autoEnableNavigationMode: Bool {
        didSet { UserDefaults.standard.set(autoEnableNavigationMode, forKey: "HUD.Capture.autoNavMode") }
    }

    private let logger: LogManager
    private let navigation: HudNavigationController
    private var stream: SCStream?
    private let outputQueue = DispatchQueue(label: "com.jjunnyy.hudcontroller.screenocr", qos: .utility)
    private var lastProcessedAt = Date.distantPast
    private var lastFilter: SCContentFilter?
    private var recoveryTask: Task<Void, Never>?
    private var pendingCandidateKey = ""
    private var pendingCandidateCount = 0
    private var lastSentKey = ""
    private var lastSentDistance = -1
    private var hasValidatedInstruction = false
    private let picker = SCContentSharingPicker.shared

    init(logger: LogManager, navigation: HudNavigationController) {
        self.logger = logger
        self.navigation = navigation
        self.autoSendToHUD = UserDefaults.standard.object(forKey: "HUD.Capture.autoSend") == nil
            ? false : UserDefaults.standard.bool(forKey: "HUD.Capture.autoSend")
        self.keepScreenAwake = UserDefaults.standard.object(forKey: "HUD.Capture.keepAwake") == nil
            ? true : UserDefaults.standard.bool(forKey: "HUD.Capture.keepAwake")
        self.autoRecoverAfterInterruption = UserDefaults.standard.object(forKey: "HUD.Capture.autoRecover") == nil
            ? true : UserDefaults.standard.bool(forKey: "HUD.Capture.autoRecover")
        self.autoEnableNavigationMode = UserDefaults.standard.object(forKey: "HUD.Capture.autoNavMode") == nil
            ? true : UserDefaults.standard.bool(forKey: "HUD.Capture.autoNavMode")
        super.init()
        picker.add(self)
    }

    deinit {
        picker.remove(self)
    }

    func presentFullDisplayPicker() {
        // On iOS 27, full-display capture is selected by calling present().
        // macOS-only picker fields such as allowedPickerModes,
        // allowsChangingSelectedContent, and excludedBundleIDs are explicitly
        // unavailable on iOS.
        var config = SCContentSharingPickerConfiguration()
        config.showsMicrophoneControl = false
        picker.defaultConfiguration = config
        picker.isActive = true

        status = "Choose Entire Display in Apple's picker"
        logger.log("SCREEN CAPTURE", "Presenting iOS 27 full-display picker")
        picker.present()
    }

    func stop() {
        recoveryTask?.cancel()
        recoveryTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
        guard let stream else {
            status = "Stopped"
            return
        }
        self.stream = nil
        stream.stopCapture { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.logger.log("SCREEN CAPTURE ERROR", error.localizedDescription)
                }
                self?.status = "Stopped"
            }
        }
    }

    func appBecameActive() {
        guard autoRecoverAfterInterruption,
              stream == nil,
              let filter = lastFilter else { return }
        logger.log("SCREEN CAPTURE RECOVERY", "App active; retrying cached full-display filter")
        start(filter: filter, recovery: true)
    }

    private func scheduleRecovery(reason: String) {
        guard autoRecoverAfterInterruption, let filter = lastFilter else { return }
        guard recoveryTask == nil else { return }
        status = "Capture interrupted — recovery pending"
        logger.log("SCREEN CAPTURE RECOVERY", "Scheduling retry: \(reason)")
        recoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, self.stream == nil else { return }
            self.recoveryTask = nil
            self.start(filter: filter, recovery: true)
        }
    }

    func hudSessionDidReset(reason: String) {
        // ScreenCaptureKit belongs to the iPhone and may still be running even
        // though the physical HUD rebooted. Reset only HUD-delivery state.
        navigationModeArmed = false
        lastSentKey = ""
        lastSentDistance = -1
        pendingCandidateKey = ""
        pendingCandidateCount = 0

        logger.log(
            "SCREEN NAV SESSION",
            "\(reason); reset HUD navigation arm/dedup state while keeping capture alive"
        )

        guard autoSendToHUD,
              autoEnableNavigationMode,
              hasValidatedInstruction,
              latestInstruction.distanceMeters > 0 else { return }

        navigation.navigationOn()
        navigationModeArmed = true
        navigation.current = latestInstruction
        navigation.sendCurrent()

        let streetKey = latestInstruction.streetName
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        lastSentKey = "\(latestInstruction.maneuver.rawValue)|\(streetKey)"
        lastSentDistance = latestInstruction.distanceMeters

        logger.log(
            "SCREEN NAV SESSION",
            "Re-armed Navigation ON and re-sent cached validated maneuver"
        )
    }

    func analyzePhoto(_ image: UIImage) async {
        status = "Analyzing saved screenshot…"
        do {
            let result = try await GoogleMapsOCRParser.recognize(image)
            apply(result, source: "PHOTO OCR")
            status = "Saved screenshot parsed"
        } catch {
            status = "Photo OCR failed"
            logger.log("OCR ERROR", error.localizedDescription)
        }
    }

    private func start(filter: SCContentFilter, recovery: Bool = false) {
        recoveryTask?.cancel()
        recoveryTask = nil
        if let existing = stream {
            existing.stopCapture(completionHandler: nil)
            stream = nil
        }
        lastFilter = filter
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        let config = SCStreamConfiguration()
        config.capturesAudio = false

        // iOS 27 marks minimumFrameInterval, queueDepth, and scalesToFit
        // unavailable. Keep the default stream configuration and throttle OCR
        // in process(pixelBuffer:) instead. We intentionally process no more
        // than roughly one frame per second regardless of stream frame rate.

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
            self.stream = newStream
            status = "Starting full-display capture…"
            newStream.startCapture { [weak self] error in
                Task { @MainActor in
                    if let error {
                        self?.status = "Capture start failed"
                        self?.logger.log("SCREEN CAPTURE ERROR", error.localizedDescription)
                    } else {
                        self?.status = recovery ? "Capture recovered" : "Capturing display; OCR ~1 Hz"
                        self?.logger.log(
                            recovery ? "SCREEN CAPTURE RECOVERY" : "SCREEN CAPTURE",
                            recovery ? "Cached-filter capture restart succeeded" : "Full-display stream started"
                        )
                    }
                }
            }
        } catch {
            status = "Capture setup failed"
            logger.log("SCREEN CAPTURE ERROR", error.localizedDescription)
        }
    }

    private func process(pixelBuffer: CVPixelBuffer) {
        // ScreenCaptureKit already throttles to ~1 Hz. This is a secondary guard.
        guard Date().timeIntervalSince(lastProcessedAt) >= 0.8 else { return }
        lastProcessedAt = Date()

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = UIImage(cgImage: cgImage)

        Task {
            do {
                let result = try await GoogleMapsOCRParser.recognize(image)
                await MainActor.run {
                    self.frameCount += 1
                    self.lastFrameAt = Date()
                    self.apply(result, source: "SCREEN OCR")
                }
            } catch {
                await MainActor.run {
                    self.logger.log("OCR ERROR", error.localizedDescription)
                }
            }
        }
    }

    private func apply(_ result: ParsedExternalNavigation, source: String) {
        latestRawText = result.rawText

        guard result.isValidNavigation else {
            rejectedFrames += 1
            logger.log(
                "SCREEN OCR REJECT",
                "confidence=\(result.confidence) reason=\(result.validationReason) rawFirst=\(result.rawText.split(separator: "\n").first ?? "")"
            )
            return
        }

        validNavigationFrames += 1
        latestInstruction = result.instruction
        hasValidatedInstruction = true
        logger.log(
            source,
            "VALID confidence=\(result.confidence) \(result.instruction.primaryText) | \(result.instruction.streetName) | \(result.instruction.distanceMeters)m"
        )

        guard autoSendToHUD && result.instruction.distanceMeters > 0 else { return }

        let streetKey = result.instruction.streetName
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        let candidateKey = "\(result.instruction.maneuver.rawValue)|\(streetKey)"

        if candidateKey == pendingCandidateKey {
            pendingCandidateCount += 1
        } else {
            pendingCandidateKey = candidateKey
            pendingCandidateCount = 1
        }

        // Two consecutive independently OCR'd valid frames are required before
        // the first packet for a new maneuver/street.
        guard pendingCandidateCount >= 2 else {
            logger.log("SCREEN OCR FILTER", "Valid candidate 1/2: \(candidateKey)")
            return
        }

        if autoEnableNavigationMode && !navigationModeArmed {
            navigationModeArmed = true
            navigation.navigationOn()
            logger.log("SCREEN NAV", "Automatically enabled HUD navigation mode")
        }

        let meaningfulDistanceChange =
            lastSentDistance < 0 || abs(result.instruction.distanceMeters - lastSentDistance) >= 10

        guard candidateKey != lastSentKey || meaningfulDistanceChange else {
            logger.log("SCREEN OCR FILTER", "Suppressed duplicate valid HUD maneuver")
            return
        }

        lastSentKey = candidateKey
        lastSentDistance = result.instruction.distanceMeters
        navigation.current = result.instruction
        navigation.sendCurrent()
        logger.log("SCREEN NAV", "Sent validated maneuver to HUD")
    }

}

@available(iOS 27.0, *)
extension ExternalNavigationCapture: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor in
            self.start(filter: filter)
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            self.status = "Picker cancelled"
            self.logger.log("SCREEN CAPTURE", "Picker cancelled")
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in
            self.status = "Picker failed"
            self.logger.log("SCREEN CAPTURE ERROR", error.localizedDescription)
        }
    }
}

@available(iOS 27.0, *)
extension ExternalNavigationCapture: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.stream = nil
            UIApplication.shared.isIdleTimerDisabled = false
            self.status = "Capture stopped by iOS/user — unlock may be required"
            let nsError = error as NSError
            self.logger.log(
                "SCREEN CAPTURE STOP",
                "domain=\(nsError.domain) code=\(nsError.code) description=\(error.localizedDescription)"
            )
            self.scheduleRecovery(reason: error.localizedDescription)
        }
    }
}

@available(iOS 27.0, *)
extension ExternalNavigationCapture: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { @MainActor in
            self.process(pixelBuffer: buffer)
        }
    }
}


#else

/// Simulator / SDK fallback.
///
/// Apple's iOS 27 ScreenCaptureKit full-display sample is device-only.
/// CI still compiles and exercises the shared Vision OCR parser through this
/// fallback, while TestFlight/device builds compile the real implementation.
@available(iOS 27.0, *)
@MainActor
@Observable
final class ExternalNavigationCapture: NSObject {
    private(set) var status = "Live screen capture requires a physical iOS 27 device"
    private(set) var latestRawText = ""
    private(set) var latestInstruction = NavigationInstruction(
        maneuver: .straight,
        distanceMeters: 0,
        primaryText: "Waiting for screenshot",
        streetName: ""
    )
    private(set) var lastFrameAt: Date?
    private(set) var frameCount = 0
    private(set) var validNavigationFrames = 0
    private(set) var rejectedFrames = 0
    private(set) var navigationModeArmed = false

    var autoSendToHUD: Bool {
        didSet {
            UserDefaults.standard.set(autoSendToHUD, forKey: "HUD.Capture.autoSend")
        }
    }
    var keepScreenAwake = false
    var autoRecoverAfterInterruption = false
    var autoEnableNavigationMode = true

    private let logger: LogManager
    private let navigation: HudNavigationController

    init(logger: LogManager, navigation: HudNavigationController) {
        self.logger = logger
        self.navigation = navigation
        self.autoSendToHUD =
            UserDefaults.standard.object(forKey: "HUD.Capture.autoSend") == nil
            ? false
            : UserDefaults.standard.bool(forKey: "HUD.Capture.autoSend")
        super.init()
    }

    func presentFullDisplayPicker() {
        status = "Live capture unavailable in Simulator — use Saved Screenshot test"
        logger.log("SCREEN CAPTURE", "Simulator fallback: live capture unavailable")
    }

    func stop() {
        status = "Stopped"
    }

    func appBecameActive() { }

    func hudSessionDidReset(reason: String) { }

    func analyzePhoto(_ image: UIImage) async {
        status = "Analyzing saved screenshot…"
        do {
            let result = try await GoogleMapsOCRParser.recognize(image)
            latestRawText = result.rawText
            latestInstruction = result.instruction
            frameCount += 1
            lastFrameAt = Date()
            status = "Saved screenshot parsed"
            logger.log(
                "PHOTO OCR",
                "\(result.instruction.primaryText) | \(result.instruction.streetName) | \(result.instruction.distanceMeters)m"
            )

            if autoSendToHUD && result.instruction.distanceMeters > 0 {
                navigation.current = result.instruction
                navigation.sendCurrent()
            }
        } catch {
            status = "Photo OCR failed"
            logger.log("OCR ERROR", error.localizedDescription)
        }
    }
}
#endif

import Foundation
import Observation
import UIKit
import Vision
import CoreMedia
import CoreVideo
import UserNotifications

#if canImport(ScreenCaptureKit) && !targetEnvironment(simulator)
import ScreenCaptureKit

@available(iOS 27.0, *)
@MainActor
@Observable
final class ExternalNavigationCapture: NSObject {
    private(set) var status = "Stopped"
    private(set) var latestRawText = ""
    private(set) var latestInstruction = NavigationInstruction(
        maneuver: .straight,
        distanceMeters: 0,
        primaryText: "Waiting for capture",
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
    private let outputQueue = DispatchQueue(
        label: "com.jjunnyy.hudcontroller.screenocr",
        qos: .utility
    )
    private var lastProcessedAt = Date.distantPast
    private var lastFilter: SCContentFilter?
    private var recoveryTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var arrivalTask: Task<Void, Never>?
    private var recoveryAttempt = 0
    private var cachedFilterFailureCount = 0
    private var captureLossGeneration = 0
    private var recoveryNotificationPermissionRequested = false
    private var automaticPickerPresentedThisSession = false
    private(set) var captureDesired: Bool {
        didSet { UserDefaults.standard.set(captureDesired, forKey: "HUD.Capture.desired") }
    }

    private var pendingCandidateKey = ""
    private var pendingCandidateCount = 0
    private var lastSentKey = ""
    private var lastSentDistance = -1
    private var hasValidatedInstruction = false

    private var explicitInactiveFrames = 0
    private var unknownFrames = 0
    private var activeFrames = 0

    private let picker = SCContentSharingPicker.shared

    init(logger: LogManager, navigation: HudNavigationController) {
        self.logger = logger
        self.navigation = navigation

        let d = UserDefaults.standard
        self.autoSendToHUD = d.object(forKey: "HUD.Capture.autoSend") == nil
            ? true : d.bool(forKey: "HUD.Capture.autoSend")
        self.keepScreenAwake = d.object(forKey: "HUD.Capture.keepAwake") == nil
            ? true : d.bool(forKey: "HUD.Capture.keepAwake")
        self.autoRecoverAfterInterruption = d.object(forKey: "HUD.Capture.autoRecover") == nil
            ? true : d.bool(forKey: "HUD.Capture.autoRecover")
        self.autoEnableNavigationMode = d.object(forKey: "HUD.Capture.autoNavMode") == nil
            ? true : d.bool(forKey: "HUD.Capture.autoNavMode")
        self.captureDesired = d.object(forKey: "HUD.Capture.desired") == nil
            ? true : d.bool(forKey: "HUD.Capture.desired")

        super.init()
        picker.add(self)
    }

    deinit {
        picker.remove(self)
    }

    func presentFullDisplayPicker() {
        captureDesired = true
        requestRecoveryNotificationPermissionIfNeeded()
        var config = SCContentSharingPickerConfiguration()
        config.showsMicrophoneControl = false
        picker.defaultConfiguration = config
        picker.isActive = true

        needsUserReselection = false
        automaticPickerPresentedThisSession = true
        status = "Choose Entire Display in Apple's picker"
        logger.log("SCREEN CAPTURE", "Presenting iOS 27 full-display picker")
        picker.present()
    }

    func stop() {
        captureDesired = false
        recoveryTask?.cancel()
        recoveryTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        arrivalTask?.cancel()
        arrivalTask = nil
        recoveryAttempt = 0
        cachedFilterFailureCount = 0
        needsUserReselection = false
        UIApplication.shared.isIdleTimerDisabled = false

        deactivateNavigation(reason: "Screen capture manually stopped")

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
        requestAutomaticStartIfDesired()
    }

    func requestAutomaticStartIfDesired() {
        guard captureDesired, autoRecoverAfterInterruption, stream == nil else { return }

        if let filter = lastFilter {
            logger.log("SCREEN CAPTURE RECOVERY", "Capture desired; retrying cached full-display filter")
            start(filter: filter, recovery: true)
            return
        }

        // SCContentFilter itself isn't persistable across process launches.
        // When no live-session filter exists, minimize intervention by
        // automatically presenting Apple's required system picker once while
        // the app is active. The user still makes the privacy-sensitive
        // Entire Display selection.
        guard UIApplication.shared.applicationState == .active,
              !automaticPickerPresentedThisSession else { return }

        logger.log("SCREEN CAPTURE AUTO", "Capture desired but a fresh system selection is required; presenting picker")
        presentFullDisplayPicker()
    }

    func hudSessionDidReset(reason: String) {
        // A physical HUD reboot does not invalidate the iPhone capture.
        navigationModeArmed = false
        lastSentKey = ""
        lastSentDistance = -1
        pendingCandidateKey = ""
        pendingCandidateCount = 0

        logger.log(
            "SCREEN NAV SESSION",
            "\(reason); reset HUD delivery state while preserving capture"
        )

        guard navigation.bluetooth.state == .connected,
              autoSendToHUD,
              autoEnableNavigationMode else { return }

        if detectedScreenState == .approachRoute {
            armNavigationIfNeeded()
            sendProceedToRoute()
            return
        }

        guard hasValidatedInstruction,
              detectedScreenState == .active,
              latestInstruction.distanceMeters > 0 else { return }

        armNavigationIfNeeded()
        navigation.current = latestInstruction
        navigation.sendCurrent()
        rememberSent(latestInstruction)

        logger.log(
            "SCREEN NAV SESSION",
            "Re-armed Navigation and re-sent cached validated maneuver"
        )
    }

    func analyzePhoto(_ image: UIImage) async {
        status = "Analyzing saved screenshot…"
        do {
            let result = try await ExternalNavigationOCRParser.recognize(image)
            apply(result, sourceLabel: "PHOTO OCR")
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

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)

        do {
            try newStream.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: outputQueue
            )
            self.stream = newStream
            status = recovery ? "Recovering full-display capture…" : "Starting full-display capture…"

            newStream.startCapture { [weak self, weak newStream] error in
                Task { @MainActor in
                    guard let self else { return }

                    if let error {
                        if self.stream === newStream {
                            self.stream = nil
                        }
                        self.status = "Capture restart failed"
                        self.logger.log(
                            "SCREEN CAPTURE ERROR",
                            "start failed: \(error.localizedDescription)"
                        )
                        self.cachedFilterFailureCount += 1
                        self.handleFailedCachedFilterIfNeeded(reason: error.localizedDescription)
                        return
                    }

                    self.captureLossGeneration += 1
                    self.recoveryAttempt = 0
                    self.cachedFilterFailureCount = 0
                    self.needsUserReselection = false
                    self.lastFrameAt = Date()
                    self.status = recovery
                        ? "Capture recovered"
                        : "Capturing display; OCR ~1 Hz"
                    self.logger.log(
                        recovery ? "SCREEN CAPTURE RECOVERY" : "SCREEN CAPTURE",
                        recovery ? "Full-display stream restart succeeded" : "Full-display stream started"
                    )
                    self.startWatchdog()
                }
            }
        } catch {
            stream = nil
            status = "Capture setup failed"
            logger.log("SCREEN CAPTURE ERROR", error.localizedDescription)
            cachedFilterFailureCount += 1
            handleFailedCachedFilterIfNeeded(reason: error.localizedDescription)
        }
    }

    private func handleFailedCachedFilterIfNeeded(reason: String) {
        guard captureDesired, autoRecoverAfterInterruption else { return }

        if cachedFilterFailureCount >= 3 {
            logger.log(
                "SCREEN CAPTURE RECOVERY",
                "Cached SCContentFilter failed \(cachedFilterFailureCount)x; invalidating it and requiring fresh Entire Display selection"
            )
            lastFilter = nil
            recoveryTask?.cancel()
            recoveryTask = nil
            needsUserReselection = true
            status = "Screen capture needs permission again — tap Resume Capture"
            forceFreerideForCaptureLoss(
                reason: "Screen capture unavailable; fresh system selection required"
            )
            notifyCaptureNeedsAttention(
                reason: "Screen capture stopped and iOS requires Entire Display to be selected again."
            )

            // iOS owns the privacy picker. Present it automatically only while
            // our app is active; otherwise the visible Resume button remains.
            if UIApplication.shared.applicationState == .active {
                automaticPickerPresentedThisSession = false
                requestAutomaticStartIfDesired()
            }
            return
        }

        scheduleRecovery(reason: reason)
    }

    private func scheduleRecovery(reason: String) {
        guard captureDesired,
              autoRecoverAfterInterruption,
              lastFilter != nil else { return }
        guard recoveryTask == nil else { return }

        recoveryAttempt += 1
        let delays = [1, 2, 4, 8, 15]
        let delay = delays[min(recoveryAttempt - 1, delays.count - 1)]

        status = "Capture interrupted — retrying in \(delay)s"
        logger.log(
            "SCREEN CAPTURE RECOVERY",
            "attempt=\(recoveryAttempt) delay=\(delay)s reason=\(reason)"
        )

        recoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.recoveryTask = nil

            guard self.stream == nil, let filter = self.lastFilter else { return }
            self.start(filter: filter, recovery: true)
        }
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard self.autoRecoverAfterInterruption,
                      self.stream != nil,
                      let lastFrameAt = self.lastFrameAt else { continue }

                let age = Date().timeIntervalSince(lastFrameAt)
                if age > 4 {
                    self.logger.log(
                        "SCREEN CAPTURE WATCHDOG",
                        "No screen frame for \(Int(age))s; rebuilding SCStream"
                    )
                    let old = self.stream
                    self.stream = nil
                    self.forceFreerideForCaptureLoss(
                        reason: "Raw ScreenCaptureKit frame heartbeat stalled"
                    )
                    old?.stopCapture(completionHandler: nil)
                    self.cachedFilterFailureCount = 0
                    self.scheduleRecovery(reason: "raw frame watchdog stale")
                    return
                }
            }
        }
    }

    private func process(pixelBuffer: CVPixelBuffer) {
        guard Date().timeIntervalSince(lastProcessedAt) >= 0.8 else { return }
        lastProcessedAt = Date()

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = UIImage(cgImage: cgImage)

        Task {
            do {
                let result = try await ExternalNavigationOCRParser.recognize(image)
                await MainActor.run {
                    self.frameCount += 1
                    self.apply(result, sourceLabel: "SCREEN OCR")
                }
            } catch {
                await MainActor.run {
                    self.logger.log("OCR ERROR", error.localizedDescription)
                }
            }
        }
    }

    private func apply(_ result: ParsedExternalNavigation, sourceLabel: String) {
        latestRawText = result.rawText
        detectedSource = result.source
        detectedScreenState = result.screenState

        logger.log(
            "NAV CLASSIFY",
            "source=\(result.source.rawValue) state=\(result.screenState.rawValue) confidence=\(result.confidence) structural=\(result.structuralConfidence)"
        )

        switch result.screenState {
        case .approachRoute:
            activeFrames += 1
            explicitInactiveFrames = 0
            unknownFrames = 0
            arrivalTask?.cancel()
            arrivalTask = nil

            if autoSendToHUD {
                armNavigationIfNeeded()
                sendProceedToRoute()
            }
            status = "\(result.source.rawValue): proceed to route"
            return

        case .arrived:
            explicitInactiveFrames = 0
            unknownFrames = 0
            showArrivalAndReturnToFreeride(reason: "Explicit arrival OCR")
            return

        case .inactive:
            explicitInactiveFrames += 1
            unknownFrames = 0
            activeFrames = 0

            logger.log(
                "SCREEN NAV LIFECYCLE",
                "Explicit inactive Maps frame \(explicitInactiveFrames)/2"
            )

            if navigationModeArmed && explicitInactiveFrames >= 2 {
                if hasValidatedInstruction && lastSentDistance >= 0 && lastSentDistance <= 80 {
                    showArrivalAndReturnToFreeride(
                        reason: "Maps returned home near destination"
                    )
                } else {
                    deactivateNavigation(reason: "Maps returned to graphical/home view")
                }
            }
            return

        case .unknown:
            rejectedFrames += 1
            unknownFrames += 1
            explicitInactiveFrames = 0

            logger.log(
                "SCREEN OCR REJECT",
                "unknown frame \(unknownFrames)/6 confidence=\(result.confidence) reason=\(result.validationReason)"
            )

            if navigationModeArmed && unknownFrames >= 6 {
                deactivateNavigation(reason: "Navigation list absent for consecutive frames")
            }
            return

        case .active:
            explicitInactiveFrames = 0
            unknownFrames = 0
            activeFrames += 1
            arrivalTask?.cancel()
            arrivalTask = nil
        }

        guard result.isValidNavigation else {
            rejectedFrames += 1
            logger.log(
                "SCREEN OCR REJECT",
                "source=\(result.source.rawValue) confidence=\(result.confidence) reason=\(result.validationReason)"
            )
            return
        }

        validNavigationFrames += 1
        latestInstruction = result.instruction
        hasValidatedInstruction = true

        logger.log(
            sourceLabel,
            "VALID source=\(result.source.rawValue) confidence=\(result.confidence) " +
            "\(result.instruction.primaryText) | \(result.instruction.streetName) | " +
            "\(result.originalDistanceText) -> \(result.instruction.distanceMeters)m"
        )

        guard autoSendToHUD && result.instruction.distanceMeters > 0 else { return }

        let candidateKey = instructionKey(result.instruction)

        if candidateKey == pendingCandidateKey {
            pendingCandidateCount += 1
        } else {
            pendingCandidateKey = candidateKey
            pendingCandidateCount = 1
        }

        // First navigation acquisition remains conservative. Once navigation
        // is armed, a structurally strong Google/Apple route list may change
        // street + turn + distance immediately during a legitimate reroute.
        let strongReroute =
            navigationModeArmed &&
            candidateKey != lastSentKey &&
            result.structuralConfidence >= 90 &&
            result.confidence >= 90

        guard pendingCandidateCount >= 2 || strongReroute else {
            logger.log(
                "SCREEN OCR FILTER",
                "candidate 1/2: \(candidateKey)"
            )
            return
        }

        armNavigationIfNeeded()

        let meaningfulDistanceChange =
            lastSentDistance < 0 ||
            abs(result.instruction.distanceMeters - lastSentDistance) >= 8

        guard candidateKey != lastSentKey || meaningfulDistanceChange else {
            logger.log("SCREEN OCR FILTER", "Suppressed duplicate valid HUD maneuver")
            return
        }

        navigation.current = result.instruction
        navigation.sendCurrent()
        rememberSent(result.instruction)

        logger.log(
            "SCREEN NAV",
            strongReroute
                ? "Accepted structurally valid reroute immediately"
                : "Sent validated maneuver to HUD"
        )
    }

    private func armNavigationIfNeeded() {
        guard autoEnableNavigationMode,
              !navigationModeArmed,
              navigation.bluetooth.state == .connected else { return }

        navigation.navigationOn()
        navigationModeArmed = true
        logger.log("SCREEN NAV", "Automatically enabled HUD navigation mode")
    }

    private func sendProceedToRoute() {
        guard navigation.bluetooth.state == .connected else { return }

        let proceed = NavigationInstruction(
            maneuver: .straight,
            distanceMeters: 0,
            primaryText: "Proceed to the route",
            streetName: ""
        )

        // Send it only once until a new active maneuver arrives.
        let key = "approachRoute"
        guard lastSentKey != key else { return }

        navigation.current = proceed
        navigation.sendCurrent()
        lastSentKey = key
        lastSentDistance = 0
        logger.log("SCREEN NAV", "Sent Proceed to route state")
    }


    private func forceFreerideForCaptureLoss(reason: String) {
        captureLossGeneration += 1
        let generation = captureLossGeneration

        // Do not trust our local navigationModeArmed flag here. A physical HUD
        // reboot can leave firmware Navigation ON while the phone believes it
        // is unarmed. Capture health is authoritative: no stream = Freeride.
        navigation.navigationOff()
        navigationModeArmed = false
        pendingCandidateKey = ""
        pendingCandidateCount = 0
        lastSentKey = ""
        lastSentDistance = -1

        logger.log(
            "SCREEN NAV LIFECYCLE",
            "FORCE Navigation OFF → Freeride: \(reason)"
        )

        // Field logs showed the first Navigation OFF packet could be missed by
        // the HUD during reconnect/firmware activity. Reassert twice, but only
        // if capture has not recovered in the meantime.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self,
                  generation == self.captureLossGeneration,
                  self.stream == nil else { return }
            self.navigation.navigationOff()

            try? await Task.sleep(for: .milliseconds(850))
            guard generation == self.captureLossGeneration,
                  self.stream == nil else { return }
            self.navigation.navigationOff()
        }
    }

    private func requestRecoveryNotificationPermissionIfNeeded() {
        guard !recoveryNotificationPermissionRequested else { return }
        recoveryNotificationPermissionRequested = true

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    private func notifyCaptureNeedsAttention(reason: String) {
        guard UIApplication.shared.applicationState != .active else { return }

        let content = UNMutableNotificationContent()
        content.title = "HUD screen capture paused"
        content.body = "Tap to reopen HUD Controller and select Entire Display to resume navigation."
        content.sound = .default
        content.userInfo = ["HUDCaptureRecovery": true, "reason": reason]

        let request = UNNotificationRequest(
            identifier: "hud.capture.recovery",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.logger.log(
                        "SCREEN CAPTURE ALERT",
                        "Local recovery notification failed: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func showArrivalAndReturnToFreeride(reason: String) {
        guard navigationModeArmed else { return }
        guard arrivalTask == nil else { return }

        logger.log("SCREEN NAV ARRIVAL", reason)

        if navigation.bluetooth.state == .connected {
            navigation.current = NavigationInstruction(
                maneuver: .destination,
                distanceMeters: 0,
                primaryText: "You have arrived",
                streetName: ""
            )
            navigation.sendCurrent()
        }

        detectedScreenState = .arrived
        arrivalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled else { return }
            self.arrivalTask = nil
            self.deactivateNavigation(reason: "Arrival display completed")
        }
    }

    private func deactivateNavigation(reason: String) {
        arrivalTask?.cancel()
        arrivalTask = nil

        if navigationModeArmed && navigation.bluetooth.state == .connected {
            navigation.navigationOff()
        }

        navigationModeArmed = false
        pendingCandidateKey = ""
        pendingCandidateCount = 0
        lastSentKey = ""
        lastSentDistance = -1
        explicitInactiveFrames = 0
        unknownFrames = 0
        activeFrames = 0

        logger.log("SCREEN NAV LIFECYCLE", "Navigation OFF → Freeride: \(reason)")
    }

    private func instructionKey(_ instruction: NavigationInstruction) -> String {
        let street = instruction.streetName
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        return "\(instruction.maneuver.rawValue)|\(street)"
    }

    private func rememberSent(_ instruction: NavigationInstruction) {
        lastSentKey = instructionKey(instruction)
        lastSentDistance = instruction.distanceMeters
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

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        Task { @MainActor in
            self.needsUserReselection = self.captureDesired
            self.status = self.captureDesired ? "Capture paused — tap Resume Capture" : "Picker cancelled"
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
            if self.stream === stream {
                self.stream = nil
            }
            self.watchdogTask?.cancel()
            self.watchdogTask = nil
            UIApplication.shared.isIdleTimerDisabled = false

            let nsError = error as NSError
            self.status = "Capture stopped — automatic recovery active"
            self.logger.log(
                "SCREEN CAPTURE STOP",
                "domain=\(nsError.domain) code=\(nsError.code) description=\(error.localizedDescription)"
            )

            // Capture health is the highest-level navigation prerequisite.
            // Never leave a stale maneuver frozen on the HUD while the source
            // pixels are unavailable. Capture recovery remains desired.
            self.forceFreerideForCaptureLoss(
                reason: "ScreenCaptureKit stream stopped unexpectedly"
            )
            self.scheduleRecovery(reason: error.localizedDescription)
        }
    }
}

@available(iOS 27.0, *)
extension ExternalNavigationCapture: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              sampleBuffer.isValid,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        Task { @MainActor in
            // Raw stream heartbeat is deliberately independent of OCR. A slow
            // Vision pass must never be mistaken for a dead SCStream.
            self.lastFrameAt = Date()
            self.process(pixelBuffer: buffer)
        }
    }
}

#else

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
    private(set) var needsUserReselection = false
    private(set) var detectedSource = ExternalNavigationSource.unknown
    private(set) var detectedScreenState = ExternalNavigationScreenState.unknown

    var autoSendToHUD: Bool {
        didSet { UserDefaults.standard.set(autoSendToHUD, forKey: "HUD.Capture.autoSend") }
    }
    var keepScreenAwake = false
    var autoRecoverAfterInterruption = false
    var autoEnableNavigationMode = true
    private(set) var captureDesired = true

    private let logger: LogManager
    private let navigation: HudNavigationController

    init(logger: LogManager, navigation: HudNavigationController) {
        self.logger = logger
        self.navigation = navigation
        self.autoSendToHUD =
            UserDefaults.standard.object(forKey: "HUD.Capture.autoSend") == nil
            ? true
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
    func requestAutomaticStartIfDesired() { }
    func hudSessionDidReset(reason: String) { }

    func analyzePhoto(_ image: UIImage) async {
        status = "Analyzing saved screenshot…"
        do {
            let result = try await ExternalNavigationOCRParser.recognize(image)
            latestRawText = result.rawText
            detectedSource = result.source
            detectedScreenState = result.screenState
            if result.isValidNavigation {
                latestInstruction = result.instruction
                validNavigationFrames += 1
            } else {
                rejectedFrames += 1
            }
            frameCount += 1
            lastFrameAt = Date()
            status = "Saved screenshot parsed"
        } catch {
            status = "Photo OCR failed"
            logger.log("OCR ERROR", error.localizedDescription)
        }
    }
}
#endif

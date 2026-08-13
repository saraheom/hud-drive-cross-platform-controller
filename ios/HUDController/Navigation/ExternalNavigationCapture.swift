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

    var autoSendToHUD: Bool {
        didSet { UserDefaults.standard.set(autoSendToHUD, forKey: "HUD.Capture.autoSend") }
    }

    private let logger: LogManager
    private let navigation: HudNavigationController
    private var stream: SCStream?
    private let outputQueue = DispatchQueue(label: "com.jjunnyy.hudcontroller.screenocr", qos: .utility)
    private var lastProcessedAt = Date.distantPast
    private let picker = SCContentSharingPicker.shared

    init(logger: LogManager, navigation: HudNavigationController) {
        self.logger = logger
        self.navigation = navigation
        self.autoSendToHUD = UserDefaults.standard.object(forKey: "HUD.Capture.autoSend") == nil
            ? false : UserDefaults.standard.bool(forKey: "HUD.Capture.autoSend")
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
        guard let stream else {
            status = "Stopped"
            return
        }
        stream.stopCapture { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.logger.log("SCREEN CAPTURE ERROR", error.localizedDescription)
                }
                self?.status = "Stopped"
                self?.stream = nil
            }
        }
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

    private func start(filter: SCContentFilter) {
        stop()
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
                        self?.status = "Capturing display at ~1 Hz"
                        self?.logger.log("SCREEN CAPTURE", "Full-display stream started")
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
        latestInstruction = result.instruction
        logger.log(source, "\(result.instruction.primaryText) | \(result.instruction.streetName) | \(result.instruction.distanceMeters)m")
        if autoSendToHUD && result.instruction.distanceMeters > 0 {
            navigation.current = result.instruction
            navigation.sendCurrent()
        }
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
            self.status = "Capture stopped"
            self.logger.log("SCREEN CAPTURE ERROR", "Stream stopped: \(error.localizedDescription)")
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

    var autoSendToHUD: Bool {
        didSet {
            UserDefaults.standard.set(autoSendToHUD, forKey: "HUD.Capture.autoSend")
        }
    }

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

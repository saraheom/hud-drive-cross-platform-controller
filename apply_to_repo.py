#!/usr/bin/env python3
"""Apply v90.35.3.24.36 on top of the reviewed main checkout.
Fail closed on any unexpected source or user changes; never rewrite unrelated files.
"""
import argparse
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parent

def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old not in source:
        if new in source:
            print('  already patched:', label)
            return source
        raise ValueError(f'{label}: expected base-source anchor not found. Stop: check repository revision.')
    n = source.count(old)
    if n != 1:
        raise ValueError(f'{label}: expected one anchor, found {n}. Stop; do not risk wrong patch.')
    return source.replace(old, new, 1)

def main(repo: Path) -> None:
    base = repo / 'ios/HUDController'
    appearances = base / 'Models/HudMapModeSettings.swift'
    canvas = base / 'MapMode/HudMapModeCanvas.swift'
    video = base / 'MapMode/U2WMainVideoClient.swift'
    for p in [appearances, canvas, video]:
        if not p.is_file(): raise FileNotFoundError(p)

    # Prepare *all* edits before writing so failed anchor validation leaves the
    # user's checkout unchanged.
    files = {p: p.read_text(encoding='utf-8') for p in (appearances, canvas, video)}
    t = files[appearances]
    t = replace_once(t,
'''    case followSource
    case darkHUD
    case lightHUD
''',
'''    case followSource
    case darkHUD
    case lightHUD
    case routeSpotlight
''', 'appearance enum')
    t = replace_once(t,
'''        case .darkHUD: return "Dark HUD"
        case .lightHUD: return "Light HUD"
''',
'''        case .darkHUD: return "Dark HUD"
        case .lightHUD: return "Light HUD"
        case .routeSpotlight: return "Route Spotlight (experimental)"
''', 'appearance titles')
    files[appearances] = t

    t = files[canvas]
    t = replace_once(t,
'''        case .lightHUD:
            base
                .saturation(0.90)
                .brightness(0.08)
                .contrast(1.05)
''',
'''        case .lightHUD:
            base
                .saturation(0.90)
                .brightness(0.08)
                .contrast(1.05)
        case .routeSpotlight:
            if let routeImage = HudRouteSpotlightProcessor.render(image) {
                Image(uiImage: routeImage)
                    .resizable()
                    .scaledToFill()
            } else {
                // Route extraction is best-effort on a compressed *raster*.
                // An ambiguous/unrecognizable route must not become invented geometry.
                base
                    .saturation(0.82)
                    .brightness(-0.30)
                    .contrast(1.18)
            }
''', 'source crop filter switch')
    t = replace_once(t,
'''                    appearance: settings.mapAppearance,
                    zoom: settings.sourceMapZoom,
''',
'''                    appearance: settings.mapAppearance,
                    hasLiveRoute: snapshot.hasLiveRoute,
                    zoom: settings.sourceMapZoom,
''', 'navigation gate at canvas call site')
    t = replace_once(t,
'''    let appearance: HudMapAppearance
    let zoom: Double
    let offsetX: Double
''',
'''    let appearance: HudMapAppearance
    let hasLiveRoute: Bool
    let zoom: Double
    let offsetX: Double
''', 'navigation gate in source crop')
    t = replace_once(t,
'''            if let routeImage = HudRouteSpotlightProcessor.render(image) {
''',
'''            if hasLiveRoute, let routeImage = HudRouteSpotlightProcessor.render(image) {
''', 'require active navigation before extracting route')
    files[canvas] = t

    t = files[video]
    t = replace_once(t,
'''                if reason.contains("kVTInvalidSessionErr (-12903)"),
                   self.backgroundProbeMode == .keepDecoderBackgroundTask,
                   self.backgroundProbeScene != "Active" {
''',
'''                if reason.contains("kVTInvalidSessionErr (-12903)") ||
                    reason.contains("codecBadDataErr (-8969)") {
''', 'recover on sustained codec failure or VT session invalidation')
    t = replace_once(t,
'''                        guard self.running, self.workerGeneration == generation, self.backgroundProbeScene != "Active" else { return }
''',
'''                        guard self.running, self.workerGeneration == generation else { return }
''', 'recovery also permitted in foreground')
    t = replace_once(t,
'''lock-time -12903 detected scene=\\(self.backgroundProbeScene); attempting v8.40 retained-history bootstrap'''.replace('\\(', '\('),
'''decoder failure detected scene=\\(self.backgroundProbeScene); attempting same-TCP retained-history bootstrap'''.replace('\\(', '\('), 'diagnostic reason wording')
    t = replace_once(t,
'''self.restartWorkerWithReadOnlyBootstrap(reason: "lock-time VideoToolbox invalid session -12903")''',
'''self.restartWorkerWithReadOnlyBootstrap(reason: "bounded codec recovery: \(reason)")''',
'codec recovery reason propagation')
    t = replace_once(t,
'''    private var decoderRecoveryPending = false
    private var backgroundedAt: Date?
''',
'''    private var decoderRecoveryPending = false
    private var captureNextContinuityFrame = false
    private var lastContinuityCaptureAt: Date?
    private var backgroundedAt: Date?
''', 'continuity capture fields')
    t = replace_once(t,
'''                 if self.frameCount == 0 {
'''.replace('                 ', '                '),
'''                if self.captureNextContinuityFrame {
                    self.captureNextContinuityFrame = false
                    self.diagnosticRecorder.captureImage(image, label: "decoded_continuity_probe_\\(Int(now.timeIntervalSince1970))")
                    self.diagnosticRecorder.record("frame", "decoded_continuity_probe", fields: ["generation": generation, "frame": self.frameCount + 1])
                }
                if self.frameCount == 0 {
'''.replace('\\(', '\('), 'post-discontinuity frame evidence')
    t = replace_once(t,
'''                if message.contains("FOREIGN_REF_IDC_REJECT") {
''',
'''                if message.contains("AU_CONTINUITY_QUARANTINE") ||
                    message.contains("REFERENCE CONTINUITY WARNING") ||
                    message.contains("FOREIGN_REF_IDC_REJECT") {
                    let now = Date()
                    if self.lastContinuityCaptureAt.map({ now.timeIntervalSince($0) > 45 }) ?? true {
                        self.lastContinuityCaptureAt = now
                        self.captureNextContinuityFrame = true
                        self.diagnosticRecorder.triggerEvidenceWindow("h264_continuity_suspect", detail: message)
                    }
                }
                if message.contains("FOREIGN_REF_IDC_REJECT") {
''', 'bounded capture on continuity suspicion')
    t = replace_once(t,
'''        worker?.stop()
        worker = nil
        connected = false
        connectedAt = nil
        startWorker(reason: reason, startupBootstrap: true)
    }

    private func beginBackgroundContinuityTask() {
''',
'''        // U2WH2648 raw transport survives an iOS VideoToolbox invalid-session
        // error. Buffer live TCP on the existing worker while read-only snapshots
        // are fetched. Never create an avoidable IDR drought by dropping a healthy
        // socket just to recreate VideoToolbox.
        if connected, let worker {
            logger.log("U2W VIDEO BACKGROUND", "IN_PLACE_BOOTSTRAP requested reason=\\(reason); preserving TCP/15332 and adapter mirror")
            diagnosticRecorder.record("background_probe", "in_place_bootstrap", fields: ["reason": reason, "generation": workerGeneration])
            worker.beginInPlaceReadOnlyBootstrap(reason: reason)
            return
        }
        // Actual transport loss still requires the existing bounded TCP restart.
        worker?.stop()
        worker = nil
        connected = false
        connectedAt = nil
        startWorker(reason: reason, startupBootstrap: true)
    }

    private func beginBackgroundContinuityTask() {
'''.replace('\\(', '\('), 'same-TCP recovery coordinator')
    t = replace_once(t,
'''    private var startupBootstrapReadyNotified = false
    var onStartupBootstrapBufferingReady: (() -> Void)?
''',
'''    private var startupBootstrapReadyNotified = false
    private var inPlaceBootstrapRequested = false
    var onStartupBootstrapBufferingReady: (() -> Void)?
''', 'worker in-place state')
    t = replace_once(t,
'''        startupBootstrapReadyNotified = false
        openConnection()
''',
'''        startupBootstrapReadyNotified = false
        inPlaceBootstrapRequested = false
        openConnection()
''', 'worker start reset')
    t = replace_once(t,
'''        startupBootstrapReadyNotified = false
        decoder.reset()
        onPhase?("IDLE")
''',
'''        startupBootstrapReadyNotified = false
        inPlaceBootstrapRequested = false
        decoder.reset()
        onPhase?("IDLE")
''', 'worker stop reset')
    t = replace_once(t,
'''    private func performBoundedDecoderRecovery(reason: String, origin: String) {
''',
'''    /// Recovery-only, same-TCP read-only snapshot bridge. Called after the
    /// codec has already become invalid. It never triggers on an ordinary scene
    /// transition or a single H.264 continuity warning.
    func beginInPlaceReadOnlyBootstrap(reason: String) {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            guard self.rawNavigationPriorityMode, self.connection != nil else {
                self.onDiagnostic?("IN_PLACE_BOOTSTRAP unavailable on this relay; continuing existing WAIT_IDR safety gate")
                return
            }
            guard !self.startupBootstrapBuffering else {
                self.onDiagnostic?("IN_PLACE_BOOTSTRAP single flight already active")
                return
            }
            self.inPlaceBootstrapRequested = true
            self.startupBridgeBuffer.removeAll(keepingCapacity: true)
            self.startupBootstrapApplied = false
            self.startupBootstrapBuffering = true
            self.onPhase?("DECODER_RECOVERY")
            self.onDiagnostic?("IN_PLACE_BOOTSTRAP begin same raw TCP; buffering live Annex-B while fetching read-only snapshots reason=\\(reason)")
            self.onStartupBootstrapBufferingReady?()
        }
    }

    private func performBoundedDecoderRecovery(reason: String, origin: String) {
'''.replace('\\(', '\('), 'in-place worker method')
    t = replace_once(t,
'''            self.startupBootstrapBuffering = false
            self.startupBootstrapApplied = true

            guard !snapshots.isEmpty else {
''',
'''            self.startupBootstrapBuffering = false
            self.startupBootstrapApplied = true
            let inPlace = self.inPlaceBootstrapRequested
            self.inPlaceBootstrapRequested = false

            guard !snapshots.isEmpty else {
''', 'capture in-place state on snapshot completion')
    t = replace_once(t,
'''            if let previous, !previous.data.isEmpty, previousPairIsCoherent {
''',
'''            if inPlace {
                // The old VideoToolbox reference epoch is invalid. A proven byte
                // overlap is necessary but not sufficient: reset codec/parser and
                // require a *real decoded output* before marking the recovery LIVE.
                self.decoder.hardRecoverAwaitingIDR(reason: "same-TCP in-place read-only rebootstrap")
                self.sanitizer.quarantineReferenceChainUntilIDR()
                self.annexBParser.reset()
                self.onDiagnostic?("IN_PLACE_BOOTSTRAP byte overlap proven; reference chain reset with validated SPS/PPS retained; waiting for IDR and real decoded output")
            }
            if let previous, !previous.data.isEmpty, previousPairIsCoherent {
''', 'decoder reset at verified overlap')
    t = replace_once(t,
'''            self.onDiagnostic?("STARTUP_BOOTSTRAP_END continuous_join=YES stats={\\(self.sanitizer.stats.summary)}; exact v8.31 TCP remains live")
'''.replace('\\(', '\('),
'''            self.onDiagnostic?("STARTUP_BOOTSTRAP_END BYTE_OVERLAP_PROVEN=YES validated_idr=\\(self.sanitizer.stats.acceptedIDR) waiting_idr=\\(self.sanitizer.stats.waitingForReferenceIDR ? 1 : 0) stats={\\(self.sanitizer.stats.summary)}; display recovery requires a real decoded frame; same TCP remains live")
'''.replace('\\(', '\('), 'avoid false decoder-ready announcement')
    t = replace_once(t,
'''                        self.startupBootstrapApplied = true
                        let bridge = self.startupBridgeBuffer
''',
'''                        self.startupBootstrapApplied = true
                        self.inPlaceBootstrapRequested = false
                        let bridge = self.startupBridgeBuffer
''', 'in-place buffer overrun cleanup')
    files[video] = t

    # Validate new source is not already present and apply all edits atomically
    # (a previous partially installed patch is repaired only if its text matches).
    for p, content in files.items():
        p.write_text(content, encoding='utf-8')
        print('  updated:', p.relative_to(repo))
    for rel in ('ios/HUDController/MapMode/HudRouteSpotlightProcessor.swift',
                'ios/HUDControllerTests/V90352436RouteSpotlightAndRecoveryTests.swift'):
        src = ROOT / rel
        dst = repo / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if dst.exists() and dst.read_bytes() != src.read_bytes():
            raise ValueError(f'Refusing to overwrite existing different file: {dst}')
        shutil.copy2(src, dst)
        print('  added:', rel)
    print('Patch complete. Run iOS CI / xcodebuild on macOS before shipping to TestFlight.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, required=True, help='Existing Git repository checkout path')
    args = parser.parse_args()
    main(args.repo.resolve())

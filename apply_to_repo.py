#!/usr/bin/env python3
"""Apply focused HUD v90.35.3.24.33 source changes to the existing GitHub repo.
Requires Python 3; no external dependencies; backups created before modification.
"""
from pathlib import Path
import sys
import shutil

BASE = Path(__file__).resolve().parent
ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
REPO = ROOT / 'ios/HUDController/MapMode/U2WMainVideoClient.swift'
SPEED = ROOT / 'ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift'
IDENTITY = ROOT / 'ios/HUDController/Vehicle/CurrentNavRoadIdentity.swift'
VERSION = 'v90.35.3.24.33'


def one(source: str, before: str, after: str, label: str) -> str:
    count = source.count(before)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly one unmodified anchor, found {count}. No changes written.')
    return source.replace(before, after, 1)


def plan_patches():
    video = REPO.read_text()
    speed = SPEED.read_text()
    identity = IDENTITY.read_text()
    # Retain the healthy raw relay and its exact-overlap startup snapshot mechanism.
    # Do not make VT invalidation a reason to tear down an otherwise healthy TCP worker.
    before = '''                // v24.32 lock-transition recovery: field evidence shows iOS may
                // invalidate the current VT session (-12903) exactly when the phone
                // locks, while TCP and the bounded background task remain alive.
                // Instead of passively waiting for the head unit to emit another IDR,
                // immediately try the v8.40 zero-copy retained-history bootstrap.
                // Single-flight + cooldown guards in restartWorkerWithReadOnlyBootstrap
                // prevent recovery fan-out. If retained history has no usable IDR, the
                // normal WAITING_FRESH_IDR behavior remains as a safe fallback.
                if reason.contains("kVTInvalidSessionErr (-12903)"),
                   self.backgroundProbeMode == .keepDecoderBackgroundTask,
                   self.backgroundProbeScene != "Active" {
                    self.backgroundProbeEvent = "Lock recovery bootstrap"
                    self.logger.log("U2W VIDEO BACKGROUND", "lock-time -12903 detected scene=\\(self.backgroundProbeScene); attempting v8.40 retained-history bootstrap")
                    self.diagnosticRecorder.record("background_probe", "lock_invalid_session_rebootstrap", fields: ["scene": self.backgroundProbeScene, "phase": self.transportPhase, "generation": generation])
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        try? await Task.sleep(for: .milliseconds(120))
                        guard self.running, self.workerGeneration == generation, self.backgroundProbeScene != "Active" else { return }
                        self.restartWorkerWithReadOnlyBootstrap(reason: "lock-time VideoToolbox invalid session -12903")
                    }
                }
'''
    after = '''                // An invalid VideoToolbox session does NOT invalidate the raw TCP
                // stream. No worker/connection restart on background lock events.
                // Foreground recovery uses the existing read-only snapshot join on
                // the same connection, then only falls back to a restart if needed.
                if reason.contains("kVTInvalidSessionErr (-12903)") {
                    if self.backgroundProbeScene == "Active" {
                        self.requestInPlaceReadOnlyBootstrap(reason: "foreground VT invalid session -12903")
                    } else {
                        self.backgroundProbeEvent = "Lock invalidated VT; raw TCP preserved"
                        self.logger.log("U2W VIDEO BACKGROUND", "lock-time -12903 scene=\\(self.backgroundProbeScene); no TCP restart; defer read-only decoder repair until stable foreground")
                        self.diagnosticRecorder.record("background_probe", "lock_invalid_session_tcp_preserved", fields: ["scene": self.backgroundProbeScene, "phase": self.transportPhase, "generation": generation])
                    }
                }
'''
    video = one(video, before, after, 'video lock recovery')
    video = one(video,
        '    private func restartWorkerWithReadOnlyBootstrap(reason: String) {',
        '''    // Single-flight, bounded, same-TCP decoder bootstrap. Uses the existing
    // overlap-verified adapter snapshot fetch; never injects CarPlay commands.
    private var lastInPlaceReadOnlyBootstrapAt: Date?

    private func requestInPlaceReadOnlyBootstrap(reason: String) {
        guard running, let worker else { return }
        let now = Date()
        if let prior = lastInPlaceReadOnlyBootstrapAt,
           now.timeIntervalSince(prior) < 18.0 {
            logger.log("U2W VIDEO RECOVERY", "INPLACE_BOOTSTRAP cooldown reason=\\(reason)")
            return
        }
        lastInPlaceReadOnlyBootstrapAt = now
        backgroundProbeEvent = "Same-TCP decoder bootstrap"
        logger.log("U2W VIDEO RECOVERY", "INPLACE_BOOTSTRAP request reason=\\(reason); raw TCP and adapter untouched")
        diagnosticRecorder.record("decoder", "inplace_bootstrap_requested", fields: ["reason": reason, "generation": workerGeneration])
        worker.beginInPlaceReadOnlyBootstrap(reason: reason)
    }

    private func restartWorkerWithReadOnlyBootstrap(reason: String) {''',
        'video in-place coordinator')
    before = '''                if !healthy {
                    self.backgroundProbeEvent = "Foreground fallback rebootstrap"
                    self.logger.log("U2W VIDEO BACKGROUND", "probe foreground health failed phase=\\(self.transportPhase) frameAge=\\(frameAge.isFinite ? String(format: "%.1f", frameAge) : "none")s; restarting iPhone worker with read-only bootstrap")
                    self.diagnosticRecorder.record("background_probe", "foreground_rebootstrap", fields: ["mode": self.backgroundProbeMode.rawValue, "phase": self.transportPhase, "frame_age": frameAge])
                    self.restartWorkerWithReadOnlyBootstrap(reason: "background probe foreground fallback")
                } else {
'''
    after = '''                if !healthy {
                    self.backgroundProbeEvent = "Foreground same-TCP bootstrap"
                    self.logger.log("U2W VIDEO BACKGROUND", "foreground stale/invalid decoder phase=\\(self.transportPhase) age=\\(frameAge.isFinite ? String(format: "%.1f", frameAge) : "none")s; requesting same-TCP read-only bootstrap first")
                    self.diagnosticRecorder.record("background_probe", "foreground_inplace_bootstrap", fields: ["mode": self.backgroundProbeMode.rawValue, "phase": self.transportPhase, "frame_age": frameAge])
                    self.requestInPlaceReadOnlyBootstrap(reason: "stable foreground decoder restoration")
                    // Let the bounded snapshot fetch and VideoToolbox decode complete
                    // before considering the old worker-restart fallback.
                    try? await Task.sleep(for: .seconds(12))
                    guard !Task.isCancelled, self.running, self.lifecycleActive,
                          self.lifecycleGeneration == generation else { return }
                    let recoveredAge = self.lastDecodedFrameAt.map { Date().timeIntervalSince($0) } ?? .infinity
                    if recoveredAge >= 2.0 && self.startupSnapshotFetchTask == nil {
                        self.logger.log("U2W VIDEO BACKGROUND", "INPLACE_BOOTSTRAP no recent frames after bounded grace; invoking legacy worker fallback")
                        self.restartWorkerWithReadOnlyBootstrap(reason: "same-TCP snapshot join did not restore frames")
                    }
                } else {
'''
    video = one(video, before, after, 'video foreground recovery')
    # The worker already provides exact current-snapshot vs live-buffer overlap.
    # Reuse that mechanism on the existing socket rather than re-opening it.
    video = one(video,
      '    fileprivate func applyStartupBootstrapSnapshots(_ snapshots: [U2WMainVideoBootstrapSnapshot]) {',
      '''    func beginInPlaceReadOnlyBootstrap(reason: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.running, self.connection != nil,
                  self.rawNavigationPriorityMode, !self.startupBootstrapBuffering else {
                self.onDiagnostic?("INPLACE_BOOTSTRAP unavailable or already active; continuing bounded live-IDR fallback")
                return
            }
            self.startupBridgeBuffer.removeAll(keepingCapacity: true)
            self.startupBootstrapBuffering = true
            self.startupBootstrapApplied = false
            self.startupBootstrapReadyNotified = true
            self.onPhase?("DECODER_RECOVERY")
            self.onStatus?("Same-TCP read-only decoder bootstrap in progress", true)
            self.onDiagnostic?("INPLACE_BOOTSTRAP_BEGIN reason=\\(reason); raw TCP stays attached, buffering fresh bytes until snapshot overlap is verified")
            self.onStartupBootstrapBufferingReady?()
        }
    }

    fileprivate func applyStartupBootstrapSnapshots(_ snapshots: [U2WMainVideoBootstrapSnapshot]) {''',
      'video same-TCP worker bootstrap')
    # Reset decode state only AFTER the snapshots prove an exact live overlap.
    video = one(video,
      '''            // PREVIOUS is safe only when its observer metadata proves it immediately
            // precedes the exact CURRENT generation we just overlap-joined to live TCP.''',
      '''            // The decoder may hold an invalid VT session or contaminated
            // reference chain. Reconstruct it only after exact overlap was proven.
            self.decoder.reset()
            self.sanitizer.reset(clearParameterSets: true)
            self.annexBParser.reset()
            self.waitingForFreshLiveIDRAfterRejectedAnchor = true
            self.onDiagnostic?("INPLACE_BOOTSTRAP_REBUILD verifiedOverlap=\\(overlap.anchorLength) rawTCP=preserved; resetting decoder/parser to replay coherent history")

            // PREVIOUS is safe only when its observer metadata proves it immediately
            // precedes the exact CURRENT generation we just overlap-joined to live TCP.''',
      'video validated snapshot rebuild')

    identity = one(identity,
      '''            "hwy": "highway", "pkwy": "parkway", "ln": "lane",''',
      '''            "hwy": "highway", "pkwy": "parkway", "expy": "expressway",
            "expwy": "expressway", "expw": "expressway", "ln": "lane",''',
      'road aliases')
    identity = one(identity,
      '''            if !candidate.isEmpty, candidate == route { return true }
''',
      '''            if !candidate.isEmpty, candidate == route { return true }
            if omittedDirectionalPrefixMatches(route, candidate) { return true }
''',
      'missing directional name match')
    identity = one(identity,
      '''    static func routeRoadMatches(_ rawRouteRoad: String, name: String?, reference: String?) -> Bool {''',
      '''    /// OSM sometimes omits a cardinal prefix that CarPlay includes (N Mascher
    /// St vs Mascher Street). Accept only when exactly one side lacks a prefix.
    /// Explicit North and South names must never match each other.
    private static func omittedDirectionalPrefixMatches(_ a: String, _ b: String) -> Bool {
        let cardinals: Set<String> = ["north", "south", "east", "west"]
        let at = a.split(separator: " ").map(String.init)
        let bt = b.split(separator: " ").map(String.init)
        guard !at.isEmpty, !bt.isEmpty else { return false }
        if cardinals.contains(at[0]), !cardinals.contains(bt[0]) {
            return Array(at.dropFirst()) == bt
        }
        if cardinals.contains(bt[0]), !cardinals.contains(at[0]) {
            return Array(bt.dropFirst()) == at
        }
        return false
    }

    static func routeRoadMatches(_ rawRouteRoad: String, name: String?, reference: String?) -> Bool {''',
      'cardinal prefix matcher')

    speed = one(speed,
      '''    private var currentNavLastMatchedRoad: String?''',
      '''    // Current+Nav only: stabilize two competing explicitly posted OSM ways.
    private var currentNavPinnedPostedWay: Int64?
    private var currentNavPendingPostedSwitch: (wayID: Int64, observations: Int)?
    private var currentNavLastMatchedRoad: String?''',
      'speed source state')
    speed = one(speed,
      '''            currentNavLastMatchedRoad = nil
            currentNavLastMatchedAt = nil''',
      '''            currentNavPinnedPostedWay = nil
            currentNavPendingPostedSwitch = nil
            currentNavLastMatchedRoad = nil
            currentNavLastMatchedAt = nil''',
      'speed state road transition')
    speed = one(speed,
      '''        scored.sort { $0.score < $1.score }
        let alternatives = nearby.sorted''',
      '''        scored.sort { $0.score < $1.score }
        var speedChangePending = false
        var selected = scored.first
        if let proposed = selected,
           let pinnedWay = currentNavPinnedPostedWay,
           let previous = scored.first(where: { $0.segment.id == pinnedWay }),
           CurrentNavSpeedSwitchPolicy.needsConfirmation(
                previousWayID: pinnedWay, proposedWayID: proposed.segment.id,
                previousKmh: previous.segment.speedKmh,
                proposedKmh: proposed.segment.speedKmh,
                previousDistanceMeters: previous.distance,
                proposedDistanceMeters: proposed.distance,
                previousHeadingErrorDegrees: previous.angle,
                proposedHeadingErrorDegrees: proposed.angle) {
            let previousCount = currentNavPendingPostedSwitch?.wayID == proposed.segment.id
                ? currentNavPendingPostedSwitch!.observations : 0
            let confirmations = previousCount + 1
            if confirmations < CurrentNavSpeedSwitchPolicy.requiredConsecutiveObservations {
                currentNavPendingPostedSwitch = (proposed.segment.id, confirmations)
                speedChangePending = true
                selected = previous
                logger.log("SPEED CURRENT NAV", "AMBIGUOUS_TAG_CHANGE currentWay=\\(pinnedWay) proposedWay=\\(proposed.segment.id) confirmations=\\(confirmations)/3; keep previously posted display, warning off")
            } else {
                currentNavPendingPostedSwitch = nil
            }
        } else {
            currentNavPendingPostedSwitch = nil
        }
        let alternatives = nearby.sorted''',
      'speed stable candidate selection')
    speed = one(speed,
      '''        guard let winner = scored.first else {''',
      '''        guard let winner = selected else {''',
      'speed selected way')
    speed = one(speed,
      '''        if directMph != nil {
            currentNavContinuityAnchor = CurrentNavSameRoadContinuity.verified(''',
      '''        if directMph != nil, !speedChangePending {
            currentNavPinnedPostedWay = chosen.id
        }
        if directMph != nil {
            currentNavContinuityAnchor = CurrentNavSameRoadContinuity.verified(''',
      'speed pin exact tagged way')
    speed = one(speed,
      '''        currentNavLastMatchedRoad = identity
        currentNavLastMatchedLimitMph = mph
        currentNavLastMatchedAt = Date()''',
      '''        if speedChangePending {
            currentNavMatchFresh = false
            currentNavDisplayHold = true
            currentNavStatusReason = "ambiguous same-road speed change; warning off until confirmed"
        }
        currentNavLastMatchedRoad = identity
        currentNavLastMatchedLimitMph = mph
        currentNavLastMatchedAt = Date()''',
      'speed disable uncertain warning')
    return {REPO: video, SPEED: speed, IDENTITY: identity}


def main():
    for f in [REPO, SPEED, IDENTITY]:
        if not f.is_file():
            raise SystemExit(f'Missing source {f}. Run from a full HUD repo checkout or pass its path.')
    if 'INPLACE_BOOTSTRAP_REBUILD' in REPO.read_text():
        raise SystemExit('Patch already applied. No files modified.')
    new_files = ['ios/HUDController/Vehicle/CurrentNavSpeedSwitchPolicy.swift',
                 'ios/HUDControllerTests/V90352433SpeedSwitchTests.swift']
    for rel in new_files:
        if (ROOT / rel).exists():
            raise SystemExit(f'New policy/test file already exists: {rel}. No files modified.')
    replacements = plan_patches()  # fail all anchors before modifying any file
    for f, content in replacements.items():
        shutil.copy2(f, f.with_suffix(f.suffix + '.pre2433.bak'))
        f.write_text(content)
    for rel in new_files:
        destination = ROOT / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(BASE / rel, destination)
    print(f'Applied {VERSION} to {ROOT}')
    print('Music UI and U2W adapter untouched. Now run iOS CI and on-device lock/unlock tests.')

if __name__ == '__main__':
    main()

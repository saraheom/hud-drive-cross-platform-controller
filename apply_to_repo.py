#!/usr/bin/env python3
"""Apply gas-station/HUD restart robustness fix on reviewed HUD main source.

Applies only to reviewed AppState blob, never to unknown revisions; atomic write.
Does not update the firmware, music UI, speed engine, or MainVideo decoder.
"""
from pathlib import Path
import hashlib
import shutil
import subprocess
import sys

PACKAGE = Path(__file__).resolve().parent
TARGET_REL = 'ios/HUDController/App/AppState.swift'
KNOWN_BLOB = '2b85f54e5917cc51a64e54cc66cb4bfb5c543066'


def git_blob_sha(body: bytes) -> str:
    return hashlib.sha1(f'blob {len(body)}\0'.encode() + body).hexdigest()


def replace_once(text: str, needle: str, replacement: str, step: str) -> str:
    count = text.count(needle)
    if count != 1:
        raise RuntimeError(f'{step}: expected one exact anchor; observed {count}. No source written.')
    return text.replace(needle, replacement, 1)


def apply(source: str) -> str:
    x = source
    x = replace_once(x,
        '''    private var hudU2WJoinRecoveryTask: Task<Void, Never>?
    private var hudU2WLastManualDisplayRetryAt = Date.distantPast''',
        '''    private var hudU2WJoinRecoveryTask: Task<Void, Never>?
    // v24.35: automatic desired-state reconciliation is separate from MainVideo.
    // A HUD power cycle may never produce a successful STA status callback, so
    // watch the current adapter MJPEG session even before the first READY event.
    private var hudU2WAutoReconcileTask: Task<Void, Never>?
    private var hudU2WAutoReconcileGeneration: UInt64 = 0
    private var hudU2WAutoReconcileSince = Date.distantPast
    private var hudU2WAutoReconcileLastRetryAt = Date.distantPast
    private var hudU2WAutoReconcileRetries = 0
    private var hudU2WAutoReconcileMissingViewerSamples = 0
    private var hudU2WLastManualDisplayRetryAt = Date.distantPast''', 'add auto-rejoin state')

    x = replace_once(x,
        '''            self.scheduleHUDRehydration(reason: "BLE transport ready")
            self.scheduleAutomaticMapModeStart(reason: "HUD BLE transport ready")''',
        '''            self.scheduleHUDRehydration(reason: "BLE transport ready")
            self.scheduleAutomaticMapModeStart(reason: "HUD BLE transport ready")
            self.startHUDU2WAutoReconciliation(reason: "BLE transport ready")''',
        'BLE connection callback')

    x = replace_once(x,
        '''            self.scheduleHUDRehydration(reason: "HUD firmware hello / physical session reset")
            // Mode 6 can emit a firmware hello. The guarded reconciler will not
            // restart a live/current attempt or issue duplicate enable requests.
            self.scheduleAutomaticMapModeStart(reason: "HUD physical session reset")''',
        '''            // Mode 6 itself can generate a firmware hello. Never send stock
            // dashboard rehydration while an established Map Mode relay is active.
            // A real physical HUD reset is reconciled against the CURRENT adapter
            // MJPEG viewer, without touching the iPhone H.264 decoder.
            if self.hudU2WLiveRelayActive {
                self.logger.log("MAP AUTO REJOIN", "HUD session hello with relay active; verify current MJPEG viewer, preserve MainVideo")
                self.startHUDU2WAutoReconciliation(reason: "HUD physical session reset")
            } else {
                self.scheduleHUDRehydration(reason: "HUD firmware hello / physical session reset")
                self.scheduleAutomaticMapModeStart(reason: "HUD physical session reset")
                self.startHUDU2WAutoReconciliation(reason: "HUD physical session reset")
            }''', 'physical reset callback')

    x = replace_once(x,
        '''            self.hudU2WJoinRecoveryTask?.cancel()
            self.hudU2WJoinRecoveryTask = nil
            self.hudSTAPersistenceTestTask?.cancel()''',
        '''            self.hudU2WJoinRecoveryTask?.cancel()
            self.hudU2WJoinRecoveryTask = nil
            self.hudU2WAutoReconcileGeneration &+= 1
            self.hudU2WAutoReconcileTask?.cancel()
            self.hudU2WAutoReconcileTask = nil
            self.hudU2WAutoReconcileSince = .distantPast
            self.hudU2WAutoReconcileLastRetryAt = .distantPast
            self.hudU2WAutoReconcileRetries = 0
            self.hudU2WAutoReconcileMissingViewerSamples = 0
            self.hudU2WDisplayHealthTask?.cancel()
            self.hudU2WDisplayHealthTask = nil
            self.hudU2WDisplayRecoveryTask?.cancel()
            self.hudU2WDisplayRecoveryTask = nil
            self.hudU2WKivicKickTask?.cancel()
            self.hudU2WKivicKickTask = nil
            self.hudSTAPersistenceTestTask?.cancel()''', 'physical BLE disconnect cleanup')

    x = replace_once(x,
        '''            scheduleAutomaticMapModeStart(reason: reason)
        } else {
            automaticMapModeAttemptedOnThisConnection = false''',
        '''            scheduleAutomaticMapModeStart(reason: reason)
            startHUDU2WAutoReconciliation(reason: "auto setting enabled: \\(reason)")
        } else {
            hudU2WAutoReconcileGeneration &+= 1
            hudU2WAutoReconcileTask?.cancel()
            hudU2WAutoReconcileTask = nil
            automaticMapModeAttemptedOnThisConnection = false''', 'automatic preference ON/OFF',)

    x = replace_once(x,
        '''        } else if saved && !hudU2WLiveRelayActive {
            scheduleAutomaticMapModeStart(reason: reason)
        }''',
        '''        } else if saved {
            if !hudU2WLiveRelayActive { scheduleAutomaticMapModeStart(reason: reason) }
            startHUDU2WAutoReconciliation(reason: "preference sync: \\(reason)")
        }''', 'foreground preference reconciliation')

    x = replace_once(x,
        '''            self.hudU2WFrameRelay.start()
            self.hudU2WLiveRelayActive = true
            self.updateMapModeIdleTimerPolicy(reason: "Map Mode relay active")''',
        '''            self.hudU2WFrameRelay.start()
            self.hudU2WLiveRelayActive = true
            self.hudU2WAutoReconcileSince = Date()
            self.hudU2WAutoReconcileLastRetryAt = .distantPast
            self.hudU2WAutoReconcileRetries = 0
            self.hudU2WAutoReconcileMissingViewerSamples = 0
            self.startHUDU2WAutoReconciliation(reason: "fresh physical Map Mode attempt")
            self.updateMapModeIdleTimerPolicy(reason: "Map Mode relay active")''', 'new relay lifecycle arm')

    x = replace_once(x,
        '''                self.hudU2WSTAStatus = "HUD frame relay unavailable — Navigation retained"
                self.hudU2WLiveRelayActive = false''',
        '''                self.hudU2WSTAStatus = "HUD frame relay unavailable — Navigation retained"
                automaticStartFailure = "iPhone JPEG relay prewarm failed"
                self.hudU2WLiveRelayActive = false''', 'prewarm auto-retry unlock')

    # The legacy one-shot recovery can run before this monitor's cooldown.
    # Recheck the CURRENT viewer before issuing mode4/mode6; read-only CGI
    # unavailable is inconclusive, never a reason to disrupt a live display.
    x = replace_once(x,
        '''            guard self.hudU2WLiveRelayActive, self.bluetooth.state == .connected else { return }

            self.hudU2WKivicKickTask?.cancel()''',
        '''            guard self.hudU2WLiveRelayActive, self.bluetooth.state == .connected else { return }

            let currentViewer = await self.u2wHUDRelayStatus()
            guard !Task.isCancelled, self.hudU2WLiveRelayActive,
                  self.bluetooth.state == .connected else { return }
            if currentViewer.currentSessionReady {
                self.hudU2WSTAConnected = true
                self.hudU2WCurrentSessionWasReady = true
                self.hudU2WReadySessionID = currentViewer.sessionID
                self.startHUDU2WDisplayHealthMonitor()
                self.logger.log("MAP AUTO REJOIN", "JOIN_ABORT current viewer already healthy session=\\(currentViewer.sessionID); MainVideo and HUD mode untouched")
                return
            }
            if currentViewer.sessionID == "—" {
                self.logger.log("MAP AUTO REJOIN", "JOIN_DEFER CGI unavailable; preserving potentially healthy HUD viewer")
                return
            }

            self.hudU2WKivicKickTask?.cancel()''', 'one-shot join recovery recheck')

    x = replace_once(x,
        '''    private func startHUDU2WDisplayHealthMonitor() {''',
        '''    /// Ongoing desired-state reconciliation. Only the HUD STA/viewer can be
    /// bounced here: do NOT stop/restart MainVideo, its TCP worker, or the JPEG
    /// ingress. Available current-session evidence (including ESTABLISHED socket)
    /// outranks firmware STA status=4/6 and prevents a destructive mode switch.
    /// HTTP failures are inconclusive, not evidence of viewer loss.
    private func startHUDU2WAutoReconciliation(reason: String) {
        guard automaticMapModeEnabled,
              bluetooth.state == .connected,
              !firmwareMaintenanceActive,
              hudU2WAutoReconcileTask == nil else { return }
        hudU2WAutoReconcileGeneration &+= 1
        let generation = hudU2WAutoReconcileGeneration
        logger.log("MAP AUTO REJOIN", "reconciler armed reason=\\(reason) generation=\\(generation)")
        hudU2WAutoReconcileTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.hudU2WAutoReconcileGeneration == generation {
                    self.hudU2WAutoReconcileTask = nil
                }
            }
            while !Task.isCancelled,
                  self.hudU2WAutoReconcileGeneration == generation,
                  self.automaticMapModeEnabled,
                  self.bluetooth.state == .connected {
                try? await Task.sleep(for: .seconds(HUDMapModeAutoRejoinPolicy.pollSeconds))
                guard !Task.isCancelled,
                      self.hudU2WAutoReconcileGeneration == generation,
                      self.automaticMapModeEnabled,
                      self.bluetooth.state == .connected else { return }
                guard !self.firmwareMaintenanceActive else { continue }
                if !self.hudU2WLiveRelayActive {
                    // Let the existing 90-second preflight handle a fresh HUD
                    // connection; never open a video stream just for this poll.
                    if !self.mapModeActive,
                       self.hudU2WSTAStatusTask == nil,
                       self.automaticMapModeStartTask == nil,
                       !self.automaticMapModeAttemptedOnThisConnection {
                        self.scheduleAutomaticMapModeStart(reason: "periodic BLE/adapter reconciliation")
                    }
                    continue
                }
                // Observe adapter viewer even while the initial HUD STA task
                // is still running. Adopting real current-session readiness
                // prevents a stale firmware status=4 from bouncing Map Mode.
                let relay = await self.u2wHUDRelayStatus()
                guard !Task.isCancelled,
                      self.hudU2WAutoReconcileGeneration == generation,
                      self.automaticMapModeEnabled,
                      self.hudU2WLiveRelayActive,
                      self.bluetooth.state == .connected else { return }
                if relay.currentSessionReady {
                    self.hudU2WAutoReconcileMissingViewerSamples = 0
                    // Relay proof supersedes the unreliable status=4/6 and
                    // is refreshed on every poll, even after an intervening
                    // stale firmware status packet temporarily cleared STA.
                    self.hudU2WSTAConnected = true
                    // The current adapter session has actually sent a frame to
                    // an ESTABLISHED viewer. Do not let a faulty STA status=4/6
                    // cause a mode4/mode6 bounce or fail-safe display fallback.
                    if !self.hudU2WCurrentSessionWasReady ||
                       self.hudU2WReadySessionID != relay.sessionID {
                        self.hudU2WCurrentSessionWasReady = true
                        self.hudU2WReadySessionID = relay.sessionID
                        self.hudU2WSTAConnected = true
                        self.hudU2WSTAStatus = "Connected — adapter-confirmed HUD map frames"
                        self.logger.log("MAP AUTO REJOIN", "ADOPT_CURRENT_VIEWER session=\\(relay.sessionID) established=1; no mode switch, MainVideo preserved")
                    }
                    self.startHUDU2WDisplayHealthMonitor()
                    continue
                }
                if relay.sessionID == "—" {
                    // No usable HTTP status: do not infer that a perfectly
                    // healthy HUD display has disconnected.
                    self.logger.log("MAP AUTO REJOIN", "CGI status unavailable; no recovery action, preserving current HUD mode")
                    continue
                }
                self.hudU2WAutoReconcileMissingViewerSamples += 1
                let elapsed = Date().timeIntervalSince(self.hudU2WAutoReconcileSince)
                let sincePrevious = Date().timeIntervalSince(self.hudU2WAutoReconcileLastRetryAt)
                let busy = self.hudU2WJoinRecoveryTask != nil ||
                    self.hudU2WDisplayRecoveryTask != nil
                let shouldRetry = HUDMapModeAutoRejoinPolicy.shouldRetry(
                    desiredModeEnabled: self.automaticMapModeEnabled,
                    bleConnected: self.bluetooth.state == .connected,
                    relayActive: self.hudU2WLiveRelayActive,
                    sessionStatusAvailable: true,
                    currentViewerReady: relay.currentSessionReady,
                    starterBusy: self.hudU2WSTAStatusTask != nil,
                    recoveryBusy: busy || self.hudU2WCurrentSessionWasReady,
                    healthRecoveryExhausted: self.hudU2WDisplayRecoveryCount >= 2,
                    secondsSinceRelayStarted: elapsed,
                    secondsSincePreviousRetry: sincePrevious,
                    consecutiveMissingViewerChecks: self.hudU2WAutoReconcileMissingViewerSamples,
                    attemptedRetries: self.hudU2WAutoReconcileRetries
                )
                guard shouldRetry else { continue }
                self.hudU2WAutoReconcileRetries += 1
                self.hudU2WAutoReconcileLastRetryAt = Date()
                self.hudU2WAutoReconcileMissingViewerSamples = 0
                // The legacy helper allowed only one recovery per relay. Its
                // original single-flight guard remains, while this outer policy
                // explicitly grants at most 3 cooled-down tries per BLE session.
                self.hudU2WAutomaticJoinRecoveryCount = 0
                self.logger.log("MAP AUTO REJOIN", "AUTO_REJOIN attempt=\\(self.hudU2WAutoReconcileRetries)/\\(HUDMapModeAutoRejoinPolicy.maximumAttemptsPerBLESession) viewerAbsent=1 session=\\(relay.sessionID) age=\\(Int(elapsed))s; mode4->6+credentials only; MainVideo preserved")
                self.scheduleHUDU2WAutomaticJoinRecovery(
                    reason: "persistent auto viewer reconciliation #\\(self.hudU2WAutoReconcileRetries)"
                )
            }
        }
    }

    private func startHUDU2WDisplayHealthMonitor() {''', 'insert independent bounded viewer reconciliation')

    x = replace_once(x,
        '''        hudU2WJoinRecoveryTask?.cancel()
        hudU2WJoinRecoveryTask = nil
        hudU2WDisplayHealthTask?.cancel()''',
        '''        hudU2WJoinRecoveryTask?.cancel()
        hudU2WJoinRecoveryTask = nil
        hudU2WAutoReconcileGeneration &+= 1
        hudU2WAutoReconcileTask?.cancel()
        hudU2WAutoReconcileTask = nil
        hudU2WAutoReconcileSince = .distantPast
        hudU2WAutoReconcileLastRetryAt = .distantPast
        hudU2WAutoReconcileRetries = 0
        hudU2WAutoReconcileMissingViewerSamples = 0
        hudU2WDisplayHealthTask?.cancel()''', 'explicit Map Mode stop cancellation')

    required = (
        'ADOPT_CURRENT_VIEWER',
        'AUTO_REJOIN attempt=',
        'HUDMapModeAutoRejoinPolicy.shouldRetry(',
        'self.hudU2WAutoReconcileGeneration == generation',
        'automaticStartFailure = "iPhone JPEG relay prewarm failed"',
        'JOIN_ABORT current viewer already healthy',
    )
    for marker in required:
        if marker not in x:
            raise RuntimeError(f'Patch postcondition absent: {marker}')
    return x


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python apply_to_repo.py <repo-root>')
    repo = Path(sys.argv[1]).resolve()
    target = repo / TARGET_REL
    if not target.is_file():
        raise RuntimeError(f'Missing {target}')
    raw = target.read_bytes()
    sha = git_blob_sha(raw)
    if sha != KNOWN_BLOB:
        raise RuntimeError(f'Unexpected AppState blob {sha}; requires {KNOWN_BLOB}; no write performed.')
    if subprocess.run(['git', '-C', str(repo), 'status', '--porcelain'], capture_output=True, text=True, check=True).stdout.strip():
        raise RuntimeError('Working tree is dirty; commit/stash before applying patch.')
    modified = apply(raw.decode('utf-8'))
    new_files = {
        repo / TARGET_REL: modified.encode('utf-8'),
        repo / 'ios/HUDController/App/HUDMapModeAutoRejoinPolicy.swift':
            (PACKAGE / 'ios/HUDController/App/HUDMapModeAutoRejoinPolicy.swift').read_bytes(),
        repo / 'ios/HUDControllerTests/V90352435AutoMapRejoinTests.swift':
            (PACKAGE / 'ios/HUDControllerTests/V90352435AutoMapRejoinTests.swift').read_bytes(),
    }
    for path in list(new_files)[1:]:
        if path.exists():
            raise RuntimeError(f'Cannot overwrite pre-existing file: {path}')
    for path, body in new_files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body)
    print('Applied v90.35.3.24.35 source changes:')
    for path in new_files:
        print(' -', path.relative_to(repo))
    subprocess.run(['git', '-C', str(repo), 'diff', '--check'], check=True)
    print('PASS: git diff --check')


if __name__ == '__main__':
    main()

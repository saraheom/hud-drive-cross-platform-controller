import Foundation
import Observation
import UIKit
import VideoToolbox
import CoreMedia
import CoreImage
import Network

/// v90.35.3.24.24 MainVideo client for U2W v8.35 bounded keyframe request + unchanged v8.34 Hard-Bounded Mirror + exact v8.31 raw relay. Navigation Mode is the safety boundary: MainVideo starts only for an explicit app-only preview or Map Mode attempt and failure never restarts/signals AppleCarPlay or Route Guidance.
///
/// U2W v8.35 leaves the proven v8.34 mirror/relay bytes unchanged and adds only a bounded native keyframe-request helper. U2W v8.34 keeps the v8.33 lossless mirror fidelity and adds a hard 8-MiB write-boundary rotation independent of SPS/IDR cadence: file rotation preserves the complete
/// successful AppleCarPlay write across an atomic inode swap, mirror writes are write-all,
/// and vectored hooks mirror only the bytes the real call actually wrote. The TCP/15332
/// transport is the exact v8.31 32-KiB raw relay: no adapter parser/cache/GOP replay, no
/// source reacquisition, no autostart, and no AppleCarPlay/Route Guidance process control.
/// The iPhone continues to own Annex-B parsing, strict semantic validation and VideoToolbox.
@MainActor
@Observable
final class U2WMainVideoClient {
    private(set) var latestFrame: UIImage?
    private(set) var status = "U2W main video idle"
    private(set) var frameCount = 0
    private(set) var connected = false
    private(set) var sourceSize = "—"
    private(set) var receivedBytes: Int64 = 0
    private(set) var rawNALCount = 0
    private(set) var acceptedNALCount = 0
    private(set) var rejectedNALCount = 0
    private(set) var acceptedSPSCount = 0
    private(set) var acceptedPPSCount = 0
    private(set) var acceptedIDRCount = 0
    private(set) var acceptedSliceCount = 0
    private(set) var networkPathSummary = "Not monitoring — video idle"
    // Kept under the old property name so existing diagnostic UI bindings remain
    // source-compatible. In v8.24 it describes the dedicated recent-IDR TCP relay.
    private(set) var adapterCacheSummary = "H.264 relay not checked"
    private(set) var transportPhase = "IDLE"
    private(set) var lastFrameAgeSeconds: Double?
    private(set) var adapterRelayConfirmedRunning = false
    private var adapterRelayVersion = "?"
    private var adapterRelayClientState = "?"
    private var adapterRelaySourceBytes: UInt64?
    private var adapterRelayLastSourceProgressAt: Date?
    private var adapterRelayConsecutiveStatusFailures = 0
    private(set) var decoderSummary = "session=none • needsIDR=1 • errors=0"

    private let preflightRequiredContinuity: TimeInterval = 300.0

    var preflightReady: Bool {
        guard connected,
              transportPhase == "LIVE",
              frameCount >= 30,
              (lastFrameAgeSeconds ?? .infinity) < 1.5,
              !decoderRecoveryPending,
              let preflightStableSince else { return false }
        return Date().timeIntervalSince(preflightStableSince) >= preflightRequiredContinuity
    }

    var preflightSummary: String {
        if preflightReady { return "LIVE • 5m continuity verified" }
        if transportPhase == "LIVE", let preflightStableSince {
            let elapsed = min(preflightRequiredContinuity, max(0, Date().timeIntervalSince(preflightStableSince)))
            return "LIVE • validating continuity \(Int(elapsed))/\(Int(preflightRequiredContinuity))s"
        }
        if transportPhase == "DECODER_RECOVERY" { return "Decoder recovery • waiting for a clean IDR" }
        if transportPhase == "WAITING_FRESH_IDR" { return "Decoder reset • waiting for fresh live IDR" }
        if transportPhase == "WAITING_LIVE_IDR" { return "Connected • waiting for decoder bootstrap IDR" }
        if transportPhase == "WAITING_RELAY" { return "Waiting for U2W MainVideo relay" }
        if transportPhase == "TCP_WAITING" { return "TCP waiting — automatic retry armed" }
        if transportPhase == "DECODER_BOOTSTRAP" { return "Live IDR received • decoder starting" }
        return "Not ready • \(transportPhase)"
    }

    var sanitizerSummary: String {
        "raw \(rawNALCount) • valid \(acceptedNALCount) • rejected \(rejectedNALCount) • " +
        "SPS \(acceptedSPSCount) PPS \(acceptedPPSCount) IDR \(acceptedIDRCount) slices \(acceptedSliceCount)"
    }

    private let logger: LogManager
    private let diagnosticRecorder: LiveMapDiagnosticRecorder
    private var worker: U2WMainVideoTCPWorker?
    private var workerGeneration = 0
    private var running = false
    private var freshnessTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var connectedAt: Date?
    private var lastDecodedFrameAt: Date?
    private var lastReceivedBytesAt: Date?
    private var lastDecoderStaleDiagnosticAt: Date?
    private var lastDecoderSoftFlushAt: Date?
    private var lastDecoderReseedAt: Date?
    private var lastSourceReconnectAt: Date?
    private var lastRelayEnsureAt: Date?
    private var lastNetworkHeartbeatAt: Date?
    private var preflightStableSince: Date?
    private var preflightPassLogged = false
    private var decoderRecoveryPending = false
    private var backgroundedAt: Date?
    private var lifecycleActive = true
    private var lifecycleGeneration: UInt64 = 0
    private var lifecycleRecoveryTask: Task<Void, Never>?
    private var keyframeRequestTask: Task<Void, Never>?
    private var lastKeyframeRequestAt: Date?
    private var keyframeRequestCount = 0
    private var keyframeRequestLastResult = "Not requested"
    private var adapterSeamObserverActive = false
    private var adapterSeamEventCount = 0
    private var adapterSeamLatest = "none"
    private var startupKeyframeScheduledWorkerGeneration = -1
    private var networkMonitors: [String: NWPathMonitor] = [:]
    private var networkSignatures: [String: String] = [:]
    private var networkStatuses: [String: String] = [:]
    private let networkPathQueue = DispatchQueue(label: "HUD.MainVideo.NetworkPath")
    private let relayStartEndpoint = URL(string: "http://192.168.50.2/cgi-bin/u2wvideo-relay-start.cgi")!
    private let relayStatusEndpoint = URL(string: "http://192.168.50.2/cgi-bin/u2wvideo-relay-status.cgi")!
    private let relayStopEndpoint = URL(string: "http://192.168.50.2/cgi-bin/u2wvideo-relay-stop.cgi")!
    private let keyframeRequestEndpoint = URL(string: "http://192.168.50.2/cgi-bin/u2wvideo-request-keyframe.cgi")!

    private let decoderStaleFrameInterval: TimeInterval = 3.0
    private let startupDecoderGraceFrameCount = 10
    private let startupDecoderGraceInterval: TimeInterval = 8.0
    private let sourceStaleInterval: TimeInterval = 15.0
    private let initialIDRWaitDiagnosticInterval: TimeInterval = 20.0
    private let sourceReconnectCooldown: TimeInterval = 15.0
    private let relayEnsureCooldown: TimeInterval = 5.0
    private let keyframeRequestCooldown: TimeInterval = 10.0
    private let startupKeyframeDelay: TimeInterval = 1.5
    private let stableForegroundDelay: TimeInterval = 0.6

    init(logger: LogManager, diagnosticRecorder: LiveMapDiagnosticRecorder) {
        self.logger = logger
        self.diagnosticRecorder = diagnosticRecorder
    }

    func start(reason: String) {
        if running {
            if worker == nil {
                beginRelayBootstrapLoop(reason: "already running / \(reason)")
            }
            return
        }
        running = true
        status = "Preparing lossless-mirror U2W MainVideo relay…"
        transportPhase = "WAITING_RELAY"
        latestFrame = nil
        frameCount = 0
        sourceSize = "—"
        receivedBytes = 0
        connectedAt = nil
        lastDecodedFrameAt = nil
        lastReceivedBytesAt = nil
        lastFrameAgeSeconds = nil
        lastDecoderStaleDiagnosticAt = nil
        lastDecoderSoftFlushAt = nil
        lastDecoderReseedAt = nil
        preflightStableSince = nil
        preflightPassLogged = false
        decoderRecoveryPending = false
        backgroundedAt = nil
        lifecycleActive = true
        lifecycleGeneration &+= 1
        lifecycleRecoveryTask?.cancel(); lifecycleRecoveryTask = nil
        keyframeRequestTask?.cancel(); keyframeRequestTask = nil
        lastKeyframeRequestAt = nil
        keyframeRequestCount = 0
        keyframeRequestLastResult = "Not requested"
        startupKeyframeScheduledWorkerGeneration = -1
        lastSourceReconnectAt = nil
        lastRelayEnsureAt = nil
        adapterRelayConfirmedRunning = false
        adapterRelayVersion = "?"
        adapterRelayClientState = "?"
        adapterRelaySourceBytes = nil
        adapterRelayLastSourceProgressAt = nil
        adapterRelayConsecutiveStatusFailures = 0
        rawNALCount = 0
        acceptedNALCount = 0
        rejectedNALCount = 0
        acceptedSPSCount = 0
        acceptedPPSCount = 0
        acceptedIDRCount = 0
        acceptedSliceCount = 0
        decoderSummary = "session=none • needsIDR=1 • errors=0"
        logger.log("U2W VIDEO", "Start reason=\(reason) architecture=v8.35-bounded-keyframe-v834-hardmirror-v831-raw-tcp-15332 base architecture=v8.34-hard-bounded-mirror-v831-raw-tcp-15332 base=v8.34-hard-8MiB-lossless-mirror/v8.31-raw/v8.27.2-observer explicitOnDemandVideoOnly=1 adapterParser=0 adapterCache=0 autostart=0 sourceReacquire=NEVER softwareDecoder=1")
        diagnosticRecorder.record("mainvideo", "start", fields: ["reason": reason, "generation": workerGeneration + 1])
        startNetworkPathLogging()
        startFreshnessWatchdog()
        beginRelayBootstrapLoop(reason: reason)
    }

    private func beginRelayBootstrapLoop(reason: String) {
        bootstrapTask?.cancel()
        bootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var attempt = 0
            while self.running, !Task.isCancelled, self.worker == nil, attempt < 3 {
                attempt += 1
                self.transportPhase = "WAITING_RELAY"
                let ready = await self.ensureAdapterRelay(reason: "bootstrap #\(attempt) / \(reason)")
                guard self.running, !Task.isCancelled else { return }
                if ready {
                    self.logger.log("MAINVIDEO PREFLIGHT", "v8.34 hard-bounded-mirror raw relay confirmed RUNNING before TCP open attempt=\(attempt)")
                    self.startWorker(reason: "relay confirmed / \(reason)")
                    return
                }
                self.status = "Waiting for explicit Map Mode recovery relay…"
                self.logger.log("MAINVIDEO PREFLIGHT", "lossless-mirror raw relay not ready attempt=\(attempt)/3; Navigation path remains independent")
                if attempt < 3 { try? await Task.sleep(for: .seconds(1)) }
            }
            if self.running, self.worker == nil {
                self.transportPhase = "FAILED_SAFE"
                self.status = "Live map unavailable — Navigation remains active"
                self.logger.log("MAINVIDEO PREFLIGHT", "FAIL CLOSED: lossless-mirror raw relay unavailable after 3 attempts; no further adapter retries")
            }
        }
    }

    @discardableResult
    func ensureAdapterRelay(reason: String) async -> Bool {
        let now = Date()
        if let lastRelayEnsureAt, now.timeIntervalSince(lastRelayEnsureAt) < relayEnsureCooldown {
            return adapterRelayConfirmedRunning
        }
        lastRelayEnsureAt = now
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 4
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: relayStartEndpoint)
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            logger.log("U2W H264 RELAY", "ensure reason=\(reason) HTTP=\(code) body={\(body.replacingOccurrences(of: "\n", with: " | "))}")
        } catch {
            logger.log("U2W H264 RELAY", "ensure failed reason=\(reason) error=\(error.localizedDescription)")
        }
        return await refreshAdapterRelayStatus(reason: "after ensure")
    }

    @discardableResult
    private func refreshAdapterRelayStatus(reason: String) async -> Bool {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(from: relayStatusEndpoint)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = String(data: data, encoding: .utf8) ?? ""
            var fields: [String: String] = [:]
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { fields[parts[0]] = parts[1] }
            }
            let process = fields["relay_process"] ?? "?"
            let legacyMarker = fields["marker"] ?? "?"
            let v835Marker = fields["v835_marker"] ?? "?"
            let v834MirrorMarker = fields["v834_mirror_marker"] ?? "?"
            let v836Marker = fields["v836_marker"] ?? "?"
            let seamCountText = fields["seam_event_count"] ?? "0"
            let seamLatest = fields["seam_latest"] ?? "none"
            let packageVersion = fields["package_version"] ?? "?"
            let relayVersion = fields["relay_version"] ?? "?"
            let clientState = fields["client_state"] ?? "?"
            let haveSPS = fields["have_sps"] ?? "?"
            let havePPS = fields["have_pps"] ?? "?"
            let idr = fields["idr"] ?? "?"
            let bootstraps = fields["client_bootstraps"] ?? fields["client_live_bootstraps"] ?? "?"
            let sendFailures = fields["client_send_failures"] ?? "?"
            let sourceBytes = fields["source_bytes_low32"] ?? "?"
            let generationChanges = fields["source_generation_changes"] ?? "?"
            adapterRelayVersion = relayVersion
            adapterRelayClientState = clientState
            adapterSeamObserverActive = v836Marker == "YES"
            if let seamCount = Int(seamCountText), seamCount != adapterSeamEventCount {
                let previous = adapterSeamEventCount
                adapterSeamEventCount = seamCount
                adapterSeamLatest = seamLatest
                logger.log("U2W VIDEO SEAM", "observer event count \(previous) → \(seamCount) latest={\(seamLatest)}")
                diagnosticRecorder.record("generation_seam", "adapter_observer_update", fields: [
                    "previous_count": previous,
                    "count": seamCount,
                    "latest": seamLatest,
                    "relay_version": relayVersion
                ])
            } else if seamLatest != "none" {
                adapterSeamLatest = seamLatest
            }
            if let parsedSourceBytes = UInt64(sourceBytes) {
                if adapterRelaySourceBytes != parsedSourceBytes {
                    adapterRelayLastSourceProgressAt = Date()
                }
                adapterRelaySourceBytes = parsedSourceBytes
            }
            adapterRelayConsecutiveStatusFailures = 0
            let droppedPreIDR = fields["pre_idr_slices_dropped"] ?? "?"
            let lastNAL = fields["last_nal_type"] ?? "?"
            let recentReady = fields["recent_anchor_valid"] ?? fields["recent_anchor_ready"] ?? "?"
            let recentBytes = fields["recent_spool_bytes"] ?? fields["recent_anchor_bytes"] ?? "?"
            let recentNals = fields["recent_spool_nals"] ?? "?"
            let recentCap = fields["recent_spool_cap"] ?? fields["recent_anchor_cap_bytes"] ?? "?"
            let recentBoots = fields["recent_bootstraps"] ?? "?"
            let recentOverflows = fields["recent_anchor_invalidations"] ?? fields["recent_anchor_overflows"] ?? "?"
            let liveIDRBoots = fields["live_idr_bootstraps"] ?? fields["client_live_bootstraps"] ?? "?"
            let lastBootstrapMode = fields["last_bootstrap_mode"] ?? "?"
            if relayVersion.contains("v8.34") || relayVersion.contains("v8.33") {
                let rawBuffer = fields["raw_buffer_bytes"] ?? "32768"
                let mirrorVersion = fields["mirror_version"] ?? "?"
                let mirrorGeneration = fields["mirror_generation"] ?? "?"
                let rotations = fields["mirror_rotation_success"] ?? "?"
                let hardRotations = fields["mirror_hard_cap_rotations"] ?? "?"
                let resourceGuards = fields["mirror_resource_guard_trips"] ?? "?"
                let fallbacks = fields["mirror_rotation_fallback_append"] ?? "?"
                let partialRetries = fields["mirror_partial_write_retries"] ?? "?"
                let writeFailures = fields["mirror_write_failures"] ?? "?"
                let tmpFree = fields["tmpfs_free_kb"] ?? "?"
                let unlatches = fields["mirror_source_unlatches"] ?? "?"
                let relatches = fields["mirror_source_relatches"] ?? "?"
                adapterCacheSummary = "\(process) • exact v8.31 raw relay \(rawBuffer)B • mirror \(mirrorVersion) gen \(mirrorGeneration) hardRot \(hardRotations)/\(rotations) guard \(resourceGuards) fallbackAppend \(fallbacks) tmpFree \(tmpFree)KB fd \(unlatches)/\(relatches) partialRetry \(partialRetries) writeFail \(writeFailures) • adapterParser NO cache NO • Navigation independent"
            } else if relayVersion.contains("v8.32") {
                let checkpointValid = fields["checkpoint_valid"] ?? "?"
                let checkpointBytes = fields["checkpoint_bytes"] ?? "?"
                let checkpointNals = fields["checkpoint_nals"] ?? "?"
                let checkpointCap = fields["checkpoint_cap_bytes"] ?? "1572864"
                let checkpointReplays = fields["checkpoint_replays"] ?? "?"
                let checkpointInvalidations = fields["checkpoint_invalidations"] ?? "?"
                let frameBreaks = fields["frame_num_discontinuities"] ?? "?"
                let falseIDR = fields["false_idr_rejects"] ?? "?"
                let scanComplete = fields["startup_scan_complete"] ?? "?"
                adapterCacheSummary = "\(process) • \(clientState) • safeCheckpoint \(checkpointValid) \(checkpointBytes)B/\(checkpointNals)NAL cap \(checkpointCap) replay \(checkpointReplays) invalid \(checkpointInvalidations) • frameBreaks \(frameBreaks) falseIDR \(falseIDR) • scanComplete \(scanComplete) • SPS \(haveSPS) PPS \(havePPS) IDR \(idr) • src \(sourceBytes)B gen \(generationChanges) • AppleCarPlay untouched"
            } else if relayVersion.contains("v8.31") {
                let rawBuffer = fields["raw_buffer_bytes"] ?? "?"
                let parser = fields["adapter_h264_parser"] ?? "?"
                let cache = fields["adapter_video_cache"] ?? "?"
                let autostart = fields["relay_autostart"] ?? "?"
                adapterCacheSummary = "\(process) • raw relay • buffer \(rawBuffer)B • adapterParser \(parser) cache \(cache) autostart \(autostart) • Navigation independent"
            } else if relayVersion.contains("v8.30") {
                let heartbeats = fields["transport_heartbeats"] ?? "?"
                let codecResets = fields["codec_epoch_resets"] ?? "?"
                let rejected = fields["rejected_nals"] ?? "?"
                let chainReady = fields["startup_chain_ready"] ?? "?"
                let chainBuilding = fields["startup_chain_building"] ?? "?"
                let chainExpired = fields["startup_chain_expired"] ?? "?"
                let chainBytes = fields["startup_chain_bytes"] ?? "?"
                let chainNals = fields["startup_chain_nals"] ?? "?"
                let chainCap = fields["startup_chain_cap_bytes"] ?? "?"
                let chainOverflows = fields["startup_chain_overflows"] ?? "?"
                let chainReplays = fields["startup_chain_replays"] ?? "?"
                adapterCacheSummary = "\(process) • \(clientState) • SPS \(haveSPS) PPS \(havePPS) • IDR \(idr) • boots \(bootstraps) • chain ready=\(chainReady) building=\(chainBuilding) expired=\(chainExpired) \(chainBytes)B/\(chainNals)NAL cap \(chainCap) overflow \(chainOverflows) replay \(chainReplays) • heartbeats \(heartbeats) codecReset \(codecResets) • rejected \(rejected) sendFail \(sendFailures) • src \(sourceBytes)B gen \(generationChanges) preIDRdrop \(droppedPreIDR) lastNAL \(lastNAL)"
            } else if relayVersion.contains("v8.27") || relayVersion.contains("v8.28") {
                let heartbeats = fields["transport_heartbeats"] ?? "?"
                let codecResets = fields["codec_epoch_resets"] ?? "?"
                let rejected = fields["rejected_nals"] ?? "?"
                adapterCacheSummary = "\(process) • \(clientState) • SPS \(haveSPS) PPS \(havePPS) • IDR \(idr) • boots \(bootstraps) • live-edge/next-IDR only • heartbeats \(heartbeats) codecReset \(codecResets) • rejected \(rejected) sendFail \(sendFailures) • src \(sourceBytes)B gen \(generationChanges) preIDRdrop \(droppedPreIDR) lastNAL \(lastNAL)"
            } else if relayVersion.contains("v8.26") {
                let cacheReady = fields["gop_cache_ready"] ?? "?"
                let cacheBuilding = fields["gop_cache_building"] ?? "?"
                let cacheOverflow = fields["gop_cache_overflow"] ?? "?"
                let cacheBytes = fields["gop_cache_bytes"] ?? "?"
                let cacheFrames = fields["gop_cache_frames"] ?? "?"
                let cacheCap = fields["gop_cache_cap"] ?? "?"
                let cacheResets = fields["gop_cache_resets"] ?? "?"
                let cacheReplays = fields["gop_cache_replays"] ?? "?"
                let cacheInvalidations = fields["gop_cache_invalidations"] ?? "?"
                let codecResets = fields["codec_epoch_resets"] ?? "?"
                let rejected = fields["rejected_nals"] ?? "?"
                adapterCacheSummary = "\(process) • \(clientState) • SPS \(haveSPS) PPS \(havePPS) • IDR \(idr) • boots \(bootstraps) cache ready=\(cacheReady) building=\(cacheBuilding) \(cacheBytes)B/\(cacheFrames)f cap \(cacheCap) overflow \(cacheOverflow) • cacheReset \(cacheResets) replay \(cacheReplays) invalid \(cacheInvalidations) codecReset \(codecResets) • liveIDR \(liveIDRBoots) mode \(lastBootstrapMode) • rejected \(rejected) sendFail \(sendFailures) • src \(sourceBytes)B gen \(generationChanges) preIDRdrop \(droppedPreIDR) lastNAL \(lastNAL)"
            } else if relayVersion.contains("v8.25") {
                let scanAttempts = fields["file_gop_scan_attempts"] ?? "?"
                let scanMisses = fields["file_gop_scan_misses"] ?? "?"
                let scanCapRejects = fields["file_gop_cap_rejects"] ?? "?"
                let fileGOPBoots = fields["file_gop_bootstraps"] ?? "?"
                let generationReseeds = fields["generation_reseeds"] ?? "?"
                let catchupCap = fields["file_gop_catchup_cap"] ?? "?"
                let catchupBytes = fields["last_bootstrap_bytes"] ?? "?"
                let catchupActive = fields["catchup_active"] ?? "?"
                let catchupProgressBytes = fields["catchup_bytes"] ?? "?"
                let catchupFrames = fields["catchup_frames"] ?? "?"
                let catchupTarget = fields["catchup_target_bytes"] ?? "?"
                let rejected = fields["rejected_nals"] ?? "?"
                adapterCacheSummary = "\(process) • \(clientState) • SPS \(haveSPS) PPS \(havePPS) • IDR \(idr) • boots \(bootstraps) fileGOP \(fileGOPBoots) liveIDR \(liveIDRBoots) mode \(lastBootstrapMode) lastCatchup \(catchupBytes)B cap \(catchupCap) • active \(catchupActive) \(catchupProgressBytes)B/\(catchupTarget) frames \(catchupFrames) • scan \(scanAttempts)/miss \(scanMisses)/cap \(scanCapRejects) genReseed \(generationReseeds) • rejected \(rejected) sendFail \(sendFailures) • src \(sourceBytes)B gen \(generationChanges) preIDRdrop \(droppedPreIDR) lastNAL \(lastNAL)"
            } else {
                adapterCacheSummary = "\(process) • \(clientState) • SPS \(haveSPS) PPS \(havePPS) • IDR \(idr) • boots \(bootstraps) recent \(recentReady)/\(recentBytes)B/\(recentNals)NAL cap \(recentCap) • recentBoots \(recentBoots) liveIDRBoots \(liveIDRBoots) mode \(lastBootstrapMode) invalid \(recentOverflows) • sendFail \(sendFailures) • src \(sourceBytes)B gen \(generationChanges) preIDRdrop \(droppedPreIDR) lastNAL \(lastNAL)"
            }
            let supportedRelay = relayVersion.contains("v8.34") || relayVersion.contains("v8.33") || relayVersion.contains("v8.32") || relayVersion.contains("v8.31") || relayVersion.contains("v8.30") || relayVersion.contains("v8.24") || relayVersion.contains("v8.25") || relayVersion.contains("v8.26") || relayVersion.contains("v8.27") || relayVersion.contains("v8.28")
            // v90.35.3.24.24: v8.35 deliberately leaves the v8.34 relay binary
            // untouched, but its wrapper status page renamed the legacy marker
            // field to v835_marker/v834_mirror_marker. v24.22 accidentally
            // required only marker=YES, so a healthy RUNNING relay was rejected
            // before TCP/15332 was ever opened. Accept either the legacy marker
            // or the paired v8.35/v8.34 markers. The relay process + supported
            // raw-relay version remain mandatory, so this does not weaken the
            // fail-closed safety boundary.
            let compatibleMarker = legacyMarker == "YES" || v835Marker == "YES" || v834MirrorMarker == "YES"
            let ready = (200...299).contains(code) && process == "RUNNING" && compatibleMarker && supportedRelay
            adapterRelayConfirmedRunning = ready
            logger.log(
                "U2W H264 RELAY",
                "status reason=\(reason) HTTP=\(code) ready=\(ready ? 1 : 0) version=\(relayVersion) package=\(packageVersion) markers={legacy=\(legacyMarker),v835=\(v835Marker),v834=\(v834MirrorMarker),v836=\(v836Marker)} seam=\(seamCountText) \(adapterCacheSummary)"
            )
            return ready
        } catch {
            adapterRelayConfirmedRunning = false
            adapterRelayConsecutiveStatusFailures += 1
            adapterCacheSummary = "H.264 relay status unavailable"
            logger.log("U2W H264 RELAY", "status failed reason=\(reason) error=\(error.localizedDescription)")
            return false
        }
    }

    private func startWorker(reason: String) {
        worker?.stop()
        workerGeneration &+= 1
        let generation = workerGeneration
        connectedAt = nil
        lastReceivedBytesAt = nil

        let worker = U2WMainVideoTCPWorker(host: "192.168.50.2", port: 15332)
        worker.onRawBytes = { [weak self] data in
            self?.diagnosticRecorder.ingestRawH264(data)
        }
        worker.onPhase = { [weak self] phase in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.workerGeneration == generation else { return }
                self.transportPhase = phase
                self.logger.log("MAINVIDEO STATE", "phase=\(phase) generation=\(generation)")
                self.diagnosticRecorder.record("transport_phase", phase, fields: ["generation": generation])
                if phase == "WAITING_LIVE_IDR", self.startupKeyframeScheduledWorkerGeneration != generation {
                    self.startupKeyframeScheduledWorkerGeneration = generation
                    self.scheduleBoundedKeyframeRequest(
                        reason: "startup has no validated IDR",
                        delay: self.startupKeyframeDelay,
                        requiredPhases: ["WAITING_LIVE_IDR", "WAITING_FRESH_IDR"]
                    )
                }
            }
        }
        worker.onStatus = { [weak self] message, isConnected in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.workerGeneration == generation else { return }
                let wasConnected = self.connected
                self.status = message
                self.connected = isConnected
                if isConnected, !wasConnected || self.connectedAt == nil { self.connectedAt = Date() }
                if !isConnected { self.connectedAt = nil }
                self.logger.log("U2W VIDEO", message)
                self.diagnosticRecorder.record("transport_status", message, fields: ["connected": isConnected, "generation": generation])
            }
        }
        worker.onBytes = { [weak self] count in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.workerGeneration == generation else { return }
                self.receivedBytes += Int64(count)
                self.lastReceivedBytesAt = Date()
            }
        }
        worker.onSanitizerStats = { [weak self] stats in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.workerGeneration == generation else { return }
                self.rawNALCount = stats.rawNALs
                self.acceptedNALCount = stats.acceptedNALs
                self.rejectedNALCount = stats.rejectedNALs
                self.acceptedSPSCount = stats.acceptedSPS
                self.acceptedPPSCount = stats.acceptedPPS
                self.acceptedIDRCount = stats.acceptedIDR
                self.acceptedSliceCount = stats.acceptedSlices
            }
        }
        worker.onDecoderState = { [weak self] summary in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.workerGeneration == generation else { return }
                if self.decoderSummary != summary {
                    self.diagnosticRecorder.record("decoder_state", summary, fields: ["generation": generation])
                }
                self.decoderSummary = summary
            }
        }
        worker.onDecoderRecovery = { [weak self] reason in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.workerGeneration == generation else { return }
                self.decoderRecoveryPending = true
                self.preflightStableSince = nil
                self.preflightPassLogged = false
                // The worker owns the precise recovery phase: first attempt is
                // DECODER_RECOVERY; a rejected recent anchor becomes
                // WAITING_FRESH_IDR without reconnecting the healthy TCP stream.
                self.logger.log("U2W VIDEO RECOVERY", reason)
                self.diagnosticRecorder.record("decoder", "recovery_requested", fields: ["reason": reason, "generation": generation])
                self.diagnosticRecorder.triggerEvidenceWindow("decoder_recovery", detail: reason)
            }
        }
        worker.onKeyframeRequestNeeded = { [weak self] reason in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.workerGeneration == generation else { return }
                self.scheduleBoundedKeyframeRequest(
                    reason: reason,
                    delay: self.stableForegroundDelay,
                    requiredPhases: ["WAITING_LIVE_IDR", "WAITING_FRESH_IDR", "DECODER_RECOVERY"]
                )
            }
        }
        worker.onFrame = { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.workerGeneration == generation else { return }
                let now = Date()
                let previousFrameAt = self.lastDecodedFrameAt
                self.latestFrame = image
                self.lastDecodedFrameAt = now
                self.lastFrameAgeSeconds = 0
                if self.frameCount == 0 {
                    self.diagnosticRecorder.captureImage(image, label: "decoded_first_frame")
                    self.diagnosticRecorder.triggerEvidenceWindow("first_decoded_frame", detail: "first VideoToolbox output")
                } else if let previousFrameAt, now.timeIntervalSince(previousFrameAt) >= 2.5 {
                    let gap = now.timeIntervalSince(previousFrameAt)
                    self.diagnosticRecorder.captureImage(image, label: "decoded_recovery_frame_\(Int(now.timeIntervalSince1970))")
                    self.diagnosticRecorder.record("frame", "recovered_after_gap", fields: ["gap_seconds": gap, "next_frame": self.frameCount + 1])
                    self.diagnosticRecorder.triggerEvidenceWindow("frame_recovered", detail: String(format: "decoded output resumed after %.1fs gap", gap))
                }
                self.lastDecoderSoftFlushAt = nil
                self.frameCount += 1
                self.transportPhase = "LIVE"
                self.decoderRecoveryPending = false
                if self.preflightStableSince == nil ||
                    previousFrameAt.map({ now.timeIntervalSince($0) > 1.5 }) == true {
                    self.preflightStableSince = now
                    self.preflightPassLogged = false
                }
                self.sourceSize = "\(Int(image.size.width))×\(Int(image.size.height))"
                self.status = "Live U2W map video • dedicated TCP relay"
                if self.frameCount == 1 || self.frameCount % 75 == 0 {
                    self.logger.log("U2W VIDEO", "Live frame #\(self.frameCount) source=\(self.sourceSize) filter={\(self.sanitizerSummary)}")
                }
            }
        }
        worker.onDiagnostic = { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.workerGeneration == generation else { return }
                self.logger.log("U2W VIDEO DEC", message)
                self.diagnosticRecorder.record("decoder_detail", message, fields: ["generation": generation])
                if message.contains("raw TCP read failed") || message.contains("raw TCP EOF") {
                    self.diagnosticRecorder.triggerEvidenceWindow("tcp_terminal", detail: message)
                } else if message.contains("codecBadDataErr") || message.contains("-12903") {
                    self.diagnosticRecorder.triggerEvidenceWindow("decoder_error", detail: message)
                }
            }
        }
        self.worker = worker
        worker.start()
        logger.log("U2W VIDEO", "TCP worker opened reason=\(reason) endpoint=192.168.50.2:15332")
    }

    private func startFreshnessWatchdog() {
        freshnessTask?.cancel()
        freshnessTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastPreflightLogAt: Date?
            while !Task.isCancelled, self.running {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, self.running else { continue }
                let now = Date()
                self.lastFrameAgeSeconds = self.lastDecodedFrameAt.map { now.timeIntervalSince($0) }

                if let frameAge = self.lastFrameAgeSeconds,
                   frameAge > 1.5 {
                    self.preflightStableSince = nil
                    self.preflightPassLogged = false
                }

                if self.preflightReady, !self.preflightPassLogged {
                    self.preflightPassLogged = true
                    self.logger.log(
                        "MAINVIDEO PREFLIGHT",
                        "PASS 5m continuous decode frames=\(self.frameCount) source=\(self.sourceSize) — extended parked validation passed"
                    )
                }

                if lastPreflightLogAt.map({ now.timeIntervalSince($0) >= 5.0 }) ?? true {
                    lastPreflightLogAt = now
                    let frameAge = self.lastFrameAgeSeconds.map { String(format: "%.1fs", $0) } ?? "none"
                    let byteAge = self.lastReceivedBytesAt.map { String(format: "%.1fs", now.timeIntervalSince($0)) } ?? "none"
                    self.logger.log("MAINVIDEO PREFLIGHT", "phase=\(self.transportPhase) ready=\(self.preflightReady ? 1 : 0) tcp=\(self.connected ? 1 : 0) bytes=\(self.receivedBytes) byteAge=\(byteAge) frames=\(self.frameCount) frameAge=\(frameAge) filter={\(self.sanitizerSummary)} decoder={\(self.decoderSummary)} relay={\(self.adapterCacheSummary)}")
                    self.diagnosticRecorder.record("heartbeat", "mainvideo", fields: [
                        "phase": self.transportPhase,
                        "connected": self.connected,
                        "received_bytes": self.receivedBytes,
                        "byte_age": byteAge,
                        "frames": self.frameCount,
                        "frame_age": frameAge,
                        "filter": self.sanitizerSummary,
                        "decoder": self.decoderSummary,
                        "relay": self.adapterCacheSummary
                    ])
                }

                let relayHealthInterval: TimeInterval = (self.adapterRelayVersion.contains("v8.30") || self.adapterRelayVersion.contains("v8.27") || self.adapterRelayVersion.contains("v8.28")) ? 60.0 : 15.0
                if self.lastNetworkHeartbeatAt.map({ now.timeIntervalSince($0) >= relayHealthInterval }) ?? true {
                    self.lastNetworkHeartbeatAt = now
                    let seconds = Int(relayHealthInterval)
                    self.logNetworkContext(reason: "\(seconds)s live-IDR MainVideo heartbeat")
                    if !self.adapterRelayVersion.contains("v8.31") { _ = await self.refreshAdapterRelayStatus(reason: "\(seconds)s MainVideo heartbeat") }
                }

                guard self.worker != nil else {
                    if self.transportPhase != "FAILED_SAFE", (self.bootstrapTask == nil || self.bootstrapTask?.isCancelled == true) {
                        self.beginRelayBootstrapLoop(reason: "watchdog worker missing")
                    }
                    continue
                }

                guard self.connected, let connectedAt = self.connectedAt else {
                    if self.adapterRelayVersion.contains("v8.31") {
                        // v90.35.3.24.15: TCP_PREPARING / TCP_WAITING /
                        // WAITING_HANDSHAKE are legitimate asynchronous startup
                        // states. The v24.14 watchdog converted them to FAILED_SAFE
                        // one second after worker creation, causing Map Mode to abort
                        // before NWConnection had a chance to connect. The worker is
                        // the authority for real failed/EOF states; AppState owns the
                        // bounded startup deadline.
                        continue
                    } else { _ = await self.ensureAdapterRelay(reason: "TCP disconnected watchdog") }
                    continue
                }

                let connectedAge = now.timeIntervalSince(connectedAt)
                let frameAge = self.lastDecodedFrameAt.map { now.timeIntervalSince($0) } ?? connectedAge
                let byteAge = self.lastReceivedBytesAt.map { now.timeIntervalSince($0) } ?? .infinity
                let bytesAreFresh = byteAge < 2.0

                // WAITING_* is a synchronization state, not a transport failure. v8.27/v8.28
                // deliberately drops undecodable P-slices until the next validated live IDR
                // and sends zero-length transport heartbeats so this same TCP session stays
                // healthy. Older v8.26 may also be intentionally quiet while preparing a
                // bootstrap. Never convert an expected decoder-wait state into reconnect churn;
                // a real socket EOF/NWConnection failure or explicit manual restart still
                // recovers the transport.
                if self.transportPhase == "WAITING_LIVE_IDR" || self.transportPhase == "WAITING_FRESH_IDR" {
                    let shouldRefresh = connectedAge >= self.initialIDRWaitDiagnosticInterval &&
                        (self.lastDecoderStaleDiagnosticAt.map({ now.timeIntervalSince($0) >= self.initialIDRWaitDiagnosticInterval }) ?? true)
                    if shouldRefresh {
                        self.lastDecoderStaleDiagnosticAt = now
                        if !self.adapterRelayVersion.contains("v8.31") { _ = await self.refreshAdapterRelayStatus(reason: "waiting decoder bootstrap") }
                        let relaySourceProgressAge = self.adapterRelayLastSourceProgressAt.map { now.timeIntervalSince($0) } ?? .infinity
                        self.logger.log(
                            "U2W VIDEO WATCH",
                            "WAITING bootstrap held on same TCP phase=\(self.transportPhase) relay=\(self.adapterRelayVersion)/\(self.adapterRelayClientState) byteAge=\(byteAge.isFinite ? String(format: "%.1f", byteAge) : "none")s sourceProgressAge=\(relaySourceProgressAge.isFinite ? String(format: "%.1f", relaySourceProgressAge) : "none")s statusFailures=\(self.adapterRelayConsecutiveStatusFailures); source-silence reconnect SUPPRESSED until real TCP failure/EOF or manual request"
                        )
                    }
                    continue
                }

                // First-stage recovery for a live source whose output callback has
                // gone quiet: ask VideoToolbox to drain any delayed/asynchronous
                // work without destroying its reference chain. If this produces a
                // frame, onFrame resets the marker and normal decode continues.
                // Startup hysteresis: the latest field run produced frame #1 at the same
                // timestamp the old 5 s startup watchdog reset VideoToolbox. Until ten
                // frames prove the decoder is in steady state, give bootstrap eight seconds
                // and do not soft-flush it out from underneath the first successful output.
                let decoderIsEstablished = self.frameCount >= self.startupDecoderGraceFrameCount
                let hardRecoveryThreshold = decoderIsEstablished ? self.decoderStaleFrameInterval : self.startupDecoderGraceInterval
                if decoderIsEstablished, bytesAreFresh, frameAge >= 1.5, frameAge < hardRecoveryThreshold,
                   self.lastDecoderSoftFlushAt == nil {
                    self.lastDecoderSoftFlushAt = now
                    self.logger.log(
                        "U2W VIDEO WATCH",
                        "NALs fresh but established decoder output age=\(String(format: "%.1f", frameAge))s; soft-flushing delayed VideoToolbox frames before hard recovery"
                    )
                    self.worker?.softFlushDecoder(reason: "fresh H.264 / established decoder stale-output soft probe")
                }

                // Once the startup grace has elapsed (or steady state has been proven),
                // a fresh H.264 source with stale VideoToolbox output is a decoder stall.
                // v8.27/v8.28 preserve the same TCP session and wait for the next clean live IDR/epoch.
                // Older compatible relays retain their bounded legacy reseed behavior.
                if bytesAreFresh, frameAge >= hardRecoveryThreshold {
                    let mayArm = self.lastDecoderReseedAt.map { now.timeIntervalSince($0) >= 10.0 } ?? true
                    if mayArm {
                        self.preflightStableSince = nil
                        self.preflightPassLogged = false
                        self.lastDecoderReseedAt = now
                        self.status = "H.264 source live — preserving decoder; future-IDR rebuild armed"
                        self.logger.log(
                            "U2W VIDEO WATCH",
                            "NALs fresh byteAge=\(String(format: "%.1f", byteAge))s frameAge=\(String(format: "%.1f", frameAge))s; decoder reference chain PRESERVED, atomic rebuild armed only at future validated IDR filter={\(self.sanitizerSummary)}"
                        )
                        self.diagnosticRecorder.record("watchdog", "decoder_output_stall", fields: ["byte_age": byteAge, "frame_age": frameAge, "filter": self.sanitizerSummary, "decoder": self.decoderSummary])
                        self.diagnosticRecorder.triggerEvidenceWindow("decoder_output_stall", detail: String(format: "fresh bytes, no decoded frame %.1fs", frameAge))
                        self.worker?.recoverDecoderAtNextIDR(
                            reason: "fresh H.264 but no decoded frame for \(String(format: "%.1f", frameAge))s"
                        )
                    }
                    continue
                }

                guard self.receivedBytes > 8, !bytesAreFresh, byteAge >= self.sourceStaleInterval else { continue }
                if self.adapterRelayVersion.contains("v8.31") {
                    self.connected = false
                    self.connectedAt = nil
                    self.transportPhase = "FAILED_SAFE"
                    self.status = "Live map source stalled — Navigation remains active"
                    self.logger.log("U2W VIDEO WATCH", "v8.31 raw source silent byteAge=\(String(format: "%.1f", byteAge))s; FAIL CLOSED, no relay ensure/reconnect")
                    self.diagnosticRecorder.record("watchdog", "raw_source_stall", fields: ["byte_age": byteAge, "received_bytes": self.receivedBytes])
                    self.diagnosticRecorder.triggerEvidenceWindow("raw_source_stall", detail: String(format: "raw TCP source silent %.1fs", byteAge))
                    continue
                }
                let mayReconnect = self.lastSourceReconnectAt.map { now.timeIntervalSince($0) >= self.sourceReconnectCooldown } ?? true
                guard mayReconnect else { continue }
                self.lastSourceReconnectAt = now
                self.connected = false
                self.connectedAt = nil
                self.status = "U2W H.264 relay silent — reconnecting for recent/live IDR bootstrap…"
                self.logger.log("U2W VIDEO WATCH", "TCP source silent byteAge=\(byteAge.isFinite ? String(format: "%.1f", byteAge) : "unknown")s; verify daemon then reconnect")
                _ = await self.ensureAdapterRelay(reason: "source silent")
                self.worker?.reconnectAtLiveEdge(reason: "source silent >=15s")
            }
        }
    }

    func applicationWillResignActive() {
        pauseDecoderForLifecycle(reason: "scene inactive")
    }

    func applicationDidEnterBackground() {
        guard running else { return }
        backgroundedAt = backgroundedAt ?? Date()
        pauseDecoderForLifecycle(reason: "scene background")
    }

    private func pauseDecoderForLifecycle(reason: String) {
        guard running else { return }
        lifecycleRecoveryTask?.cancel(); lifecycleRecoveryTask = nil
        keyframeRequestTask?.cancel(); keyframeRequestTask = nil
        lifecycleGeneration &+= 1
        let wasActive = lifecycleActive
        lifecycleActive = false
        preflightStableSince = nil
        preflightPassLogged = false
        if wasActive {
            worker?.suspendDecoderForLifecycle(reason: reason)
        }
        logger.log(
            "U2W VIDEO LIFECYCLE",
            "Lifecycle pause reason=\(reason); raw TCP/source PRESERVED, VideoToolbox session intentionally invalidated, VCL decode paused until stable foreground. generation=\(lifecycleGeneration)"
        )
        diagnosticRecorder.record("lifecycle", "decoder_paused", fields: ["reason": reason, "generation": lifecycleGeneration])
    }

    func applicationDidBecomeActive() {
        guard running else { return }
        let now = Date()
        let backgroundDuration = backgroundedAt.map { now.timeIntervalSince($0) }
        backgroundedAt = nil
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        lifecycleActive = true
        lifecycleRecoveryTask?.cancel()
        logger.log(
            "U2W VIDEO LIFECYCLE",
            "Scene active candidate generation=\(generation); waiting \(String(format: "%.1f", stableForegroundDelay))s for stable foreground before rebuilding VideoToolbox. backgroundDuration=\(backgroundDuration.map { String(format: "%.1f", $0) } ?? "none")"
        )
        diagnosticRecorder.record("lifecycle", "active_candidate", fields: ["generation": generation, "background_seconds": backgroundDuration ?? -1])
        lifecycleRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(Int(self.stableForegroundDelay * 1000)))
            guard !Task.isCancelled, self.running, self.lifecycleActive, self.lifecycleGeneration == generation else { return }
            self.worker?.resumeDecoderAfterLifecycle(reason: "stable foreground generation \(generation)")
            self.logger.log("U2W VIDEO LIFECYCLE", "Stable foreground confirmed generation=\(generation); decoder rebuilt awaiting IDR; TCP remained continuous")
            self.diagnosticRecorder.record("lifecycle", "stable_active_resume", fields: ["generation": generation])
        }
    }

    private func scheduleBoundedKeyframeRequest(reason: String, delay: TimeInterval, requiredPhases: Set<String>) {
        keyframeRequestTask?.cancel()
        let generation = lifecycleGeneration
        keyframeRequestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if delay > 0 { try? await Task.sleep(for: .milliseconds(Int(delay * 1000))) }
            guard !Task.isCancelled,
                  self.running,
                  self.lifecycleActive,
                  self.lifecycleGeneration == generation,
                  requiredPhases.contains(self.transportPhase) else { return }
            await self.requestBoundedKeyframe(reason: reason)
        }
    }

    private func requestBoundedKeyframe(reason: String) async {
        guard running, lifecycleActive else { return }
        // v90.35.3.24.24 / U2W v8.36: the Oct-5 field drive proved that the
        // v8.35 helper used SOCK_DGRAM against stock Unix SOCK_STREAM listeners
        // and always returned send_failed/route=none.  Keep the installed v8.35
        // helper for rollback provenance, but do not keep injecting the known-wrong
        // transport while the passive seam observer is active.  The exact stock
        // ARMadb-driver stream handshake/framing is being recovered offline.
        if adapterSeamObserverActive {
            keyframeRequestLastResult = "Deferred • v8.36 passive observer; stock stream IPC not yet proven"
            logger.log("U2W KEYFRAME", "DEFERRED reason=\(reason) v8.36 passive observer active; v8.35 SOCK_DGRAM route proven invalid; no IPC injection attempted")
            diagnosticRecorder.record("keyframe", "deferred_unverified_stream_ipc", fields: [
                "reason": reason,
                "seam_event_count": adapterSeamEventCount,
                "seam_latest": adapterSeamLatest
            ])
            return
        }
        let now = Date()
        if let lastKeyframeRequestAt, now.timeIntervalSince(lastKeyframeRequestAt) < keyframeRequestCooldown {
            let remaining = keyframeRequestCooldown - now.timeIntervalSince(lastKeyframeRequestAt)
            logger.log("U2W KEYFRAME", "SUPPRESSED cooldown reason=\(reason) remaining=\(String(format: "%.1f", remaining))s")
            diagnosticRecorder.record("keyframe", "suppressed_cooldown", fields: ["reason": reason, "remaining_seconds": remaining])
            return
        }
        lastKeyframeRequestAt = now
        keyframeRequestCount += 1
        let requestNumber = keyframeRequestCount
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(from: keyframeRequestEndpoint)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            keyframeRequestLastResult = "HTTP \(code) • \(body.replacingOccurrences(of: "\n", with: " | "))"
            logger.log("U2W KEYFRAME", "bounded request #\(requestNumber) reason=\(reason) HTTP=\(code) body={\(body.replacingOccurrences(of: "\n", with: " | "))}; no process restart/reconnect")
            diagnosticRecorder.record("keyframe", "request", fields: ["number": requestNumber, "reason": reason, "http": code, "body": body])
        } catch {
            keyframeRequestLastResult = "Failed • \(error.localizedDescription)"
            logger.log("U2W KEYFRAME", "bounded request #\(requestNumber) FAILED reason=\(reason) error=\(error.localizedDescription); no retry loop")
            diagnosticRecorder.record("keyframe", "request_failed", fields: ["number": requestNumber, "reason": reason, "error": error.localizedDescription])
        }
    }

    func stop(reason: String) {
        guard running || worker != nil else { status = "U2W main video idle"; return }
        running = false
        freshnessTask?.cancel(); freshnessTask = nil
        bootstrapTask?.cancel(); bootstrapTask = nil
        lifecycleRecoveryTask?.cancel(); lifecycleRecoveryTask = nil
        keyframeRequestTask?.cancel(); keyframeRequestTask = nil
        worker?.stop(); worker = nil
        workerGeneration &+= 1
        connected = false
        transportPhase = "IDLE"
        lastFrameAgeSeconds = nil
        latestFrame = nil
        connectedAt = nil
        lastDecodedFrameAt = nil
        lastReceivedBytesAt = nil
        lastNetworkHeartbeatAt = nil
        stopNetworkPathLogging(reason: reason)
        status = "U2W main video idle"
        logger.log("U2W VIDEO", "Stop reason=\(reason); dedicated TCP client closed; requesting standalone MainVideo relay exit")
        Task { @MainActor [weak self] in await self?.stopAdapterRelay(reason: reason) }
    }

    private func stopAdapterRelay(reason: String) async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(from: relayStopEndpoint)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            logger.log("U2W H264 RELAY", "stop reason=\(reason) HTTP=\(code) body={\(body.replacingOccurrences(of: "\n", with: " | "))}")
        } catch {
            logger.log("U2W H264 RELAY", "stop request failed reason=\(reason) error=\(error.localizedDescription); no retry")
        }
    }

    func reconnect(reason: String = "manual") {
        guard running else {
            status = "MainVideo predecode is not active"
            logger.log("U2W VIDEO", "Ignored reconnect while video idle reason=\(reason)")
            return
        }
        connected = false
        connectedAt = nil
        lastSourceReconnectAt = Date()
        status = "Reconnecting dedicated U2W H.264 relay…"
        logger.log("U2W VIDEO", "Manual TCP reconnect reason=\(reason)")
        Task { @MainActor [weak self] in _ = await self?.ensureAdapterRelay(reason: "manual reconnect") }
        worker?.reconnectAtLiveEdge(reason: "manual / \(reason)")
    }

    private func startNetworkPathLogging() {
        stopNetworkPathLogging(reason: "restart")
        networkStatuses = ["default": "pending", "wifi": "pending", "cellular": "pending"]
        networkPathSummary = "default pending • Wi-Fi pending • cellular pending"
        let specs: [(String, NWPathMonitor)] = [
            ("default", NWPathMonitor()),
            ("wifi", NWPathMonitor(requiredInterfaceType: .wifi)),
            ("cellular", NWPathMonitor(requiredInterfaceType: .cellular)),
        ]
        for (label, monitor) in specs {
            monitor.pathUpdateHandler = { [weak self] path in
                Task { @MainActor [weak self] in self?.handleNetworkPathUpdate(label: label, path: path) }
            }
            networkMonitors[label] = monitor
            monitor.start(queue: networkPathQueue)
        }
        logger.log("IPHONE NETWORK", "Started network monitors while continuous MainVideo predecode is active")
    }

    private func stopNetworkPathLogging(reason: String) {
        guard !networkMonitors.isEmpty else { networkPathSummary = "Not monitoring — video idle"; return }
        for monitor in networkMonitors.values { monitor.cancel() }
        networkMonitors.removeAll(); networkSignatures.removeAll(); networkStatuses.removeAll()
        networkPathSummary = "Not monitoring — video idle"
        logger.log("IPHONE NETWORK", "Stopped NWPathMonitor reason=\(reason)")
    }

    private func handleNetworkPathUpdate(label: String, path: NWPath) {
        guard running else { return }
        let value: String
        switch path.status {
        case .satisfied: value = "satisfied"
        case .unsatisfied: value = "unsatisfied"
        case .requiresConnection: value = "requiresConnection"
        @unknown default: value = "unknown"
        }
        let activeTypes = [
            path.usesInterfaceType(.wifi) ? "wifi" : nil,
            path.usesInterfaceType(.cellular) ? "cellular" : nil,
            path.usesInterfaceType(.wiredEthernet) ? "ethernet" : nil,
            path.usesInterfaceType(.loopback) ? "loopback" : nil,
            path.usesInterfaceType(.other) ? "other" : nil,
        ].compactMap { $0 }
        let available = path.availableInterfaces.map { "\(networkInterfaceTypeName($0.type)):\($0.name)" }.sorted().joined(separator: ",")
        let signature = "status=\(value) active=[\(activeTypes.joined(separator: ","))] available=[\(available)] expensive=\(path.isExpensive ? 1 : 0) constrained=\(path.isConstrained ? 1 : 0) ipv4=\(path.supportsIPv4 ? 1 : 0) ipv6=\(path.supportsIPv6 ? 1 : 0) dns=\(path.supportsDNS ? 1 : 0)"
        networkStatuses[label] = value
        networkPathSummary = "default \(networkStatuses["default"] ?? "pending") • Wi-Fi \(networkStatuses["wifi"] ?? "pending") • cellular \(networkStatuses["cellular"] ?? "pending")"
        guard networkSignatures[label] != signature else { return }
        networkSignatures[label] = signature
        logger.log("IPHONE NETWORK", "\(label) path changed \(signature)")
    }

    private func networkInterfaceTypeName(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: return "wifi"
        case .cellular: return "cellular"
        case .wiredEthernet: return "ethernet"
        case .loopback: return "loopback"
        case .other: return "other"
        @unknown default: return "unknown"
        }
    }

    private func logNetworkContext(reason: String) {
        let now = Date()
        let byteAge = lastReceivedBytesAt.map { now.timeIntervalSince($0) }
        let frameAge = lastDecodedFrameAt.map { now.timeIntervalSince($0) }
        let byteAgeText = byteAge.map { String(format: "%.1fs", $0) } ?? "none"
        let frameAgeText = frameAge.map { String(format: "%.1fs", $0) } ?? "none"
        logger.log("IPHONE NETWORK", "context reason=\(reason) summary={\(networkPathSummary)} tcp15332=\(connected ? 1 : 0) bytes=\(receivedBytes) byteAge=\(byteAgeText) frames=\(frameCount) frameAge=\(frameAgeText) h264={\(sanitizerSummary)}")
    }
}

/// Dedicated TCP/15332 worker.  The adapter already provides explicit NAL
/// boundaries, so the iPhone no longer has to recover Annex-B boundaries from a
/// Boa byte stream. Syntax validation remains on the iPhone before VideoToolbox.
private final class U2WMainVideoTCPWorker {
    let host: NWEndpoint.Host
    let port: NWEndpoint.Port
    var onStatus: ((String, Bool) -> Void)?
    var onPhase: ((String) -> Void)?
    var onBytes: ((Int) -> Void)?
    var onRawBytes: ((Data) -> Void)?
    var onFrame: ((UIImage) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onSanitizerStats: ((H264MainVideoSanitizerStats) -> Void)?
    var onDecoderState: ((String) -> Void)?
    var onDecoderRecovery: ((String) -> Void)?
    var onKeyframeRequestNeeded: ((String) -> Void)?

    private let sanitizer = H264MainVideoSanitizer()
    private let annexBParser = AnnexBH264Parser()
    private let decoder = H264VideoToolboxDecoder()
    private let queue = DispatchQueue(label: "HUD.U2WMainVideo.TCP15332", qos: .userInitiated)
    private var connection: NWConnection?
    private var running = false
    private var reconnectWorkItem: DispatchWorkItem?
    private var waitingDeadlineWorkItem: DispatchWorkItem?
    private var lastStatsEmitUptime: TimeInterval = 0
    private var connectionGeneration = 0
    private var firstAcceptedIDRForConnection = false
    // v90.35.3.24.9: keep the legacy bounded reseed path only for pre-v8.27 relays. One adapter-side
    // recovery seed is allowed per decoder-stall episode. v8.26
    // serves its persistent validated GOP cache; older v8.25/v8.24 relays fall back
    // to their file-GOP/recent-anchor strategies. If the seed produces no frame,
    // preserve the healthy TCP stream and wait for a genuinely new live IDR.
    private var recentAnchorRecoveryUsed = false
    private var waitingForFreshLiveIDRAfterRejectedAnchor = false
    private var liveIDROnlyRecovery = false
    private var relayHeartbeatCount = 0
    private var rawNavigationPriorityMode = false
    private var boundedCheckpointRecovery = false
    private var lifecyclePaused = false
    // All deployed dedicated relays use the same [u32BE length][NAL] framing.
    // v8.26 adds U2WH2644; v8.27 adds U2WH2645; v8.28 adds U2WH2646 for source-epoch-fenced fd reacquisition while keeping
    // v8.24/v8.25 compatibility so an app update cannot strand an older adapter.
    private let acceptedMagics: Set<Data> = [
        Data("U2WH2642".utf8),
        Data("U2WH2643".utf8),
        Data("U2WH2644".utf8),
        Data("U2WH2645".utf8),
        Data("U2WH2646".utf8),
        Data("U2WH2647".utf8),
        Data("U2WH2648".utf8),
        Data("U2WH2649".utf8),
    ]
    private let magicLength = 8
    private let maximumNALBytes = 512 * 1024

    init(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
        decoder.onFrame = { [weak self] image in
            guard let self else { return }
            if self.recentAnchorRecoveryUsed || self.waitingForFreshLiveIDRAfterRejectedAnchor {
                self.onDiagnostic?("Decoder produced a frame after bounded recovery; recovery-seed retry budget reset")
            }
            self.recentAnchorRecoveryUsed = false
            self.waitingForFreshLiveIDRAfterRejectedAnchor = false
            self.onFrame?(image)
        }
        decoder.onDiagnostic = { [weak self] message in self?.onDiagnostic?(message) }
        decoder.onRecoveryNeeded = { [weak self] reason in
            guard let self else { return }
            self.queue.async { [weak self] in
                guard let self, self.running else { return }
                self.performBoundedDecoderRecovery(reason: reason, origin: "VideoToolbox callback")
            }
        }
    }

    func start() {
        guard !running else { return }
        running = true
        recentAnchorRecoveryUsed = false
        waitingForFreshLiveIDRAfterRejectedAnchor = false
        relayHeartbeatCount = 0
        sanitizer.reset()
        annexBParser.reset()
        rawNavigationPriorityMode = false
        boundedCheckpointRecovery = false
        lifecyclePaused = false
        decoder.reset()
        openConnection()
    }

    func stop() {
        running = false
        reconnectWorkItem?.cancel(); reconnectWorkItem = nil
        waitingDeadlineWorkItem?.cancel(); waitingDeadlineWorkItem = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel(); connection = nil
        recentAnchorRecoveryUsed = false
        waitingForFreshLiveIDRAfterRejectedAnchor = false
        relayHeartbeatCount = 0
        sanitizer.reset()
        annexBParser.reset()
        rawNavigationPriorityMode = false
        boundedCheckpointRecovery = false
        lifecyclePaused = false
        decoder.reset()
        onPhase?("IDLE")
    }

    func suspendDecoderForLifecycle(reason: String) {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            guard !self.lifecyclePaused else { return }
            self.lifecyclePaused = true
            self.waitingForFreshLiveIDRAfterRejectedAnchor = true
            self.decoder.suspendForLifecycle(reason: reason)
            self.emitDecoderState()
            self.onPhase?("LIFECYCLE_PAUSED")
            self.onStatus?("App lifecycle transition • raw MainVideo preserved, decoder paused", true)
            self.onDiagnostic?("LIFECYCLE PAUSE reason=\(reason); TCP + Annex-B stream PRESERVED; VideoToolbox invalidated intentionally; VCL decode gated until stable foreground")
        }
    }

    func resumeDecoderAfterLifecycle(reason: String) {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            guard self.lifecyclePaused else { return }
            self.lifecyclePaused = false
            self.sanitizer.quarantineReferenceChainUntilIDR()
            self.decoder.hardRecoverAwaitingIDR(reason: reason)
            self.waitingForFreshLiveIDRAfterRejectedAnchor = true
            self.onDecoderRecovery?("lifecycle resume: \(reason)")
            self.emitDecoderState()
            self.onPhase?("WAITING_FRESH_IDR")
            self.onStatus?("Foreground stable • waiting for fresh live IDR", true)
            self.onDiagnostic?("LIFECYCLE RESUME reason=\(reason); rebuilt VideoToolbox from last validated SPS/PPS when available; TCP PRESERVED")
            self.onKeyframeRequestNeeded?("lifecycle resume needs fresh IDR")
        }
    }

    func reconnectAtLiveEdge(reason: String) {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            self.onDiagnostic?("TCP live-edge reconnect requested reason=\(reason)")
            // A real/manual transport restart begins a new recovery episode.
            self.recentAnchorRecoveryUsed = false
            self.waitingForFreshLiveIDRAfterRejectedAnchor = false
            self.closeCurrentConnection()
            self.sanitizer.prepareForTransportReconnect()
            // Preserve the last-known-good VT session, but require the next live IDR
            // before VCL decode resumes after a transport boundary.
            self.decoder.prepareForStreamRestart()
            self.scheduleReconnect(reason: reason, delay: 0.25)
        }
    }

    func softFlushDecoder(reason: String) {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            self.onDiagnostic?("Decoder soft-flush requested reason=\(reason)")
            self.decoder.finishDelayedFramesForStallProbe()
            self.emitDecoderState()
        }
    }

    func recoverDecoderAtNextIDR(reason: String) {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            self.decoder.armRebuildAtNextIDR(reason: reason)
            self.emitDecoderState()
            self.onDiagnostic?("stale-output watchdog: existing decoder/reference chain PRESERVED; atomic rebuild armed only for a future validated IDR")
        }
    }

    private func performBoundedDecoderRecovery(reason: String, origin: String) {
        let sourceEpochCorruption = reason.contains("codecBadDataErr (-8969)")
        let invalidVideoToolboxSession = reason.contains("kVTInvalidSessionErr (-12903)")
        if invalidVideoToolboxSession, liveIDROnlyRecovery {
            if lifecyclePaused {
                decoder.suspendForLifecycle(reason: reason)
                onDecoderRecovery?(reason)
                emitDecoderState()
                onPhase?("LIFECYCLE_PAUSED")
                onStatus?("VideoToolbox invalid during lifecycle transition • waiting for stable foreground", true)
                onDiagnostic?("\(origin): kVTInvalidSessionErr (-12903) while lifecycle-paused; TCP PRESERVED; decoder recreation deferred until stable foreground")
                return
            }
            sanitizer.quarantineReferenceChainUntilIDR()
            decoder.hardRecoverAwaitingIDR(reason: reason)
            waitingForFreshLiveIDRAfterRejectedAnchor = true
            onDecoderRecovery?(reason)
            emitDecoderState()
            onPhase?("WAITING_FRESH_IDR")
            onStatus?("VideoToolbox session replaced • requesting one fresh IDR", true)
            onDiagnostic?("\(origin): kVTInvalidSessionErr (-12903); rebuilt decoder from last validated SPS/PPS when available; TCP PRESERVED; one bounded native keyframe request armed")
            onKeyframeRequestNeeded?("VideoToolbox invalid session -12903")
            return
        }
        if boundedCheckpointRecovery {
            decoder.hardRecoverAwaitingFreshCodecEpoch(reason: reason)
            sanitizer.reset(clearParameterSets: true)
            onDecoderRecovery?(reason)
            emitDecoderState()
            if !recentAnchorRecoveryUsed {
                recentAnchorRecoveryUsed = true
                waitingForFreshLiveIDRAfterRejectedAnchor = false
                onPhase?("DECODER_RECOVERY")
                onStatus?("Decoder reset • reacquiring validated v8.32 checkpoint", true)
                onDiagnostic?("\(origin): v8.32 bounded recovery; discarded poisoned decoder epoch and reconnecting TCP ONCE for the adapter's validated current-generation checkpoint")
                closeCurrentConnection()
                scheduleReconnect(reason: "v8.32 safe-checkpoint recovery", delay: 0.25)
            } else {
                waitingForFreshLiveIDRAfterRejectedAnchor = true
                onPhase?("WAITING_FRESH_IDR")
                onStatus?("Recovery checkpoint did not decode • waiting for a newer genuine IDR", true)
                onDiagnostic?("\(origin): v8.32 checkpoint already attempted in this recovery episode; no reconnect loop, waiting for adapter to form a newer safe checkpoint")
            }
            return
        }
        if sourceEpochCorruption, liveIDROnlyRecovery {
            // 2026-10-01 field evidence is stronger than the earlier fresh-epoch
            // hypothesis: the same TCP/raw source stayed healthy and VideoToolbox
            // recovered when its session was rebuilt at a later IDR. SPS/PPS are
            // not guaranteed to repeat at every IDR, so preserve the last validated
            // parameter-set pair, quarantine dependent P-frames, and rebuild at the
            // very next validated IDR. This minimizes blackout time without touching
            // the healthy v8.31 TCP relay.
            sanitizer.quarantineReferenceChainUntilIDR()
            decoder.hardRecoverAwaitingIDR(reason: reason)
            waitingForFreshLiveIDRAfterRejectedAnchor = true
            onDecoderRecovery?(reason)
            emitDecoderState()
            onPhase?("WAITING_FRESH_IDR")
            onStatus?("Decoder reset • waiting for next validated IDR", true)
            onDiagnostic?("\(origin): codecBadDataErr (-8969) reset VideoToolbox + reference chain; validated SPS/PPS PRESERVED; TCP PRESERVED; waiting for next validated IDR")
            return
        }

        decoder.hardRecoverAwaitingIDR(reason: reason)
        onDecoderRecovery?(reason)
        emitDecoderState()

        // v8.27/v8.28/v8.29/v8.30 deliberately avoid decoder-error historical replay. A decoder
        // reset therefore stays on the same healthy TCP stream and waits for the
        // next naturally arriving validated live IDR. Reconnecting would only
        // replace a healthy client and cannot improve the bootstrap boundary.
        if liveIDROnlyRecovery {
            waitingForFreshLiveIDRAfterRejectedAnchor = true
            onPhase?("WAITING_FRESH_IDR")
            onStatus?("Decoder reset • waiting for next live IDR", true)
            onDiagnostic?("\(origin): relay-aware live-IDR wait (v8.27/v8.28/v8.29/v8.30); TCP PRESERVED, no GOP replay/reconnect requested")
            return
        }

        if !recentAnchorRecoveryUsed {
            recentAnchorRecoveryUsed = true
            waitingForFreshLiveIDRAfterRejectedAnchor = false
            onPhase?("DECODER_RECOVERY")
            onStatus?("Decoder recovery • one persistent-GOP reseed", true)
            onDiagnostic?("\(origin): bounded recovery attempt #1; reconnecting TCP once so v8.26 can replay its persistent validated GOP cache (older relays use file-GOP/recent-anchor fallback)")
            sanitizer.prepareForTransportReconnect()
            scheduleReconnect(reason: "bounded decoder recovery persistent-GOP reseed", delay: 0.35)
            return
        }

        // The bounded recent anchor has already been tried during this recovery
        // episode and no decoded frame proved it good. Do not reconnect and ask
        // the relay to replay the same state again. Keep receiving the live edge;
        // the decoder's needsIDR gate discards P-frames until the next true IDR.
        waitingForFreshLiveIDRAfterRejectedAnchor = true
        onPhase?("WAITING_FRESH_IDR")
        onStatus?("Recovery seed rejected • waiting for fresh live IDR", true)
        onDiagnostic?("\(origin): persistent/validated recovery seed already used and produced no frame; TCP PRESERVED, quarantining replay and waiting for next live IDR")
    }

    private func openConnection() {
        guard running else { return }
        reconnectWorkItem?.cancel(); reconnectWorkItem = nil
        waitingDeadlineWorkItem?.cancel(); waitingDeadlineWorkItem = nil
        sanitizer.prepareForTransportReconnect()
        decoder.prepareForStreamRestart()
        firstAcceptedIDRForConnection = false
        connectionGeneration &+= 1
        let generation = connectionGeneration
        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection
        onPhase?("TCP_PREPARING")
        onStatus?("Opening U2W MainVideo TCP/15332…", false)
        onDiagnostic?("TCP state generation=\(generation) OPEN endpoint=192.168.50.2:15332")

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.running, self.connection === connection, self.connectionGeneration == generation else { return }
            switch state {
            case .setup:
                self.onPhase?("TCP_PREPARING")
                self.onDiagnostic?("TCP state generation=\(generation) SETUP")
            case .preparing:
                self.onPhase?("TCP_PREPARING")
                self.onDiagnostic?("TCP state generation=\(generation) PREPARING")
            case .waiting(let error):
                self.onPhase?("TCP_WAITING")
                self.onStatus?("U2W H.264 TCP waiting: \(error.localizedDescription)", false)
                self.onDiagnostic?("TCP state generation=\(generation) WAITING error=\(error.localizedDescription); 4s retry deadline armed")
                self.armWaitingDeadline(connection: connection, generation: generation)
            case .ready:
                self.waitingDeadlineWorkItem?.cancel(); self.waitingDeadlineWorkItem = nil
                self.onPhase?("WAITING_HANDSHAKE")
                self.onStatus?("U2W H.264 TCP connected • checking relay handshake", true)
                self.onDiagnostic?("TCP state generation=\(generation) READY")
                self.receiveHandshake(connection, generation: generation)
            case .failed(let error):
                self.onPhase?("RECONNECT_DELAY")
                self.onStatus?("U2W H.264 TCP failed: \(error.localizedDescription)", false)
                self.onDiagnostic?("TCP state generation=\(generation) FAILED error=\(error.localizedDescription)")
                if self.rawNavigationPriorityMode {
                    self.onPhase?("FAILED_SAFE")
                    self.onStatus?("Live map TCP failed — Navigation remains active", false)
                } else { self.scheduleReconnect(reason: "NWConnection failed", delay: 1.0) }
            case .cancelled:
                self.onDiagnostic?("TCP state generation=\(generation) CANCELLED")
                if self.running, !self.rawNavigationPriorityMode { self.scheduleReconnect(reason: "NWConnection cancelled", delay: 1.0) }
            @unknown default:
                self.onDiagnostic?("TCP state generation=\(generation) UNKNOWN")
            }
        }
        connection.start(queue: queue)
    }

    private func armWaitingDeadline(connection: NWConnection, generation: Int) {
        waitingDeadlineWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self, weak connection] in
            guard let self, let connection, self.running, self.connection === connection, self.connectionGeneration == generation else { return }
            self.onDiagnostic?("TCP WAITING deadline expired generation=\(generation); recreating NWConnection")
            self.scheduleReconnect(reason: "TCP waiting >4s", delay: 0.5)
        }
        waitingDeadlineWorkItem = item
        queue.asyncAfter(deadline: .now() + 4.0, execute: item)
    }

    private func receiveHandshake(_ connection: NWConnection, generation: Int) {
        receiveExactly(magicLength, from: connection, generation: generation) { [weak self] data in
            guard let self else { return }
            let text = String(data: data, encoding: .ascii) ?? data.map { String(format: "%02X", $0) }.joined()
            guard self.acceptedMagics.contains(data) else {
                self.onDiagnostic?("Invalid TCP relay magic={\(text)} expected={U2WH2642...U2WH2649}; reconnecting")
                self.scheduleReconnect(reason: "invalid relay magic", delay: 1.0)
                return
            }
            if text == "U2WH2649" {
                self.rawNavigationPriorityMode = false
                self.liveIDROnlyRecovery = false
                self.boundedCheckpointRecovery = true
                self.onPhase?("WAITING_LIVE_IDR")
                self.onStatus?("U2W v8.32 connected • synchronizing safe bounded checkpoint", true)
                self.onDiagnostic?("TCP relay handshake U2WH2649 accepted; strict validator + 1.5 MiB current-generation checkpoint; no historical scan/source reacquire/AppleCarPlay control")
            } else if text == "U2WH2648" {
                self.rawNavigationPriorityMode = true
                self.liveIDROnlyRecovery = true
                self.boundedCheckpointRecovery = false
                self.annexBParser.reset()
                self.onPhase?("WAITING_LIVE_IDR")
                self.onStatus?("U2W raw relay connected • iPhone parsing lossless mirror", true)
                self.onDiagnostic?("TCP relay handshake U2WH2648 accepted; v8.35 package keeps exact v8.31 raw relay + unchanged v8.34 hard-bounded mirror; adapter parser/cache=NONE; raw Annex-B parsing owned by iPhone; mirror rotation is lossless/atomic")
                self.receiveRawBytes(connection, generation: generation)
                return
            } else if text == "U2WH2647" {
                self.boundedCheckpointRecovery = false
                self.liveIDROnlyRecovery = true
                self.onPhase?("WAITING_LIVE_IDR")
                self.onStatus?("U2W v8.30 connected • synchronizing validated reference chain", true)
                self.onDiagnostic?("TCP relay handshake U2WH2647 accepted; stateful 800×480 parser + bounded complete startup reference-chain spool; zero-length transport heartbeats enabled")
            } else if text == "U2WH2646" {
                self.boundedCheckpointRecovery = false
                self.liveIDROnlyRecovery = true
                self.onPhase?("WAITING_LIVE_IDR")
                self.onStatus?("U2W v8.28 connected • waiting for clean source epoch", true)
                self.onDiagnostic?("TCP relay handshake U2WH2646 accepted; safe fd-reacquire/source-epoch relay; zero-length transport heartbeats enabled")
            } else if text == "U2WH2645" {
                self.boundedCheckpointRecovery = false
                self.liveIDROnlyRecovery = true
                self.onPhase?("WAITING_LIVE_IDR")
                self.onStatus?("U2W relay connected • waiting for next validated live IDR", true)
                self.onDiagnostic?("TCP relay handshake U2WH2645 accepted; lightweight live-edge/next-IDR relay with zero-length transport heartbeats")
            } else {
                self.boundedCheckpointRecovery = false
                self.liveIDROnlyRecovery = false
                self.onPhase?("WAITING_LIVE_IDR")
                self.onStatus?("U2W relay connected • waiting for cached/validated/live IDR bootstrap", true)
                self.onDiagnostic?("TCP relay handshake \(text) accepted; validated/recent/live IDR bootstrap enabled")
            }
            self.receiveLength(connection, generation: generation)
        }
    }

    private func receiveLength(_ connection: NWConnection, generation: Int) {
        receiveExactly(4, from: connection, generation: generation) { [weak self] header in
            guard let self else { return }
            let length = header.reduce(0) { ($0 << 8) | Int($1) }
            if length == 0 {
                self.relayHeartbeatCount += 1
                if self.relayHeartbeatCount == 1 || self.relayHeartbeatCount % 30 == 0 {
                    self.onDiagnostic?("live-IDR relay transport heartbeat #\(self.relayHeartbeatCount) generation=\(generation) phase=\(self.waitingForFreshLiveIDRAfterRejectedAnchor ? "WAITING_FRESH_IDR" : "connected")")
                }
                self.receiveLength(connection, generation: generation)
                return
            }
            guard length <= self.maximumNALBytes else {
                self.onDiagnostic?("Invalid framed NAL length=\(length); reconnecting for live IDR bootstrap")
                self.scheduleReconnect(reason: "invalid NAL length", delay: 1.0)
                return
            }
            self.receiveNAL(length: length, connection: connection, generation: generation)
        }
    }

    private func receiveNAL(length: Int, connection: NWConnection, generation: Int) {
        receiveExactly(length, from: connection, generation: generation) { [weak self] nal in
            guard let self else { return }
            self.processNAL(nal, generation: generation)
            self.emitSanitizerStats()
            self.receiveLength(connection, generation: generation)
        }
    }

    private func receiveRawBytes(_ connection: NWConnection, generation: Int) {
        guard running, self.connection === connection, self.connectionGeneration == generation else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection, self.running, self.connection === connection, self.connectionGeneration == generation else { return }
            if let data, !data.isEmpty {
                self.onBytes?(data.count)
                self.onRawBytes?(data)
                for nal in self.annexBParser.append(data) { self.processNAL(nal, generation: generation) }
                self.emitSanitizerStats()
            }
            if let error {
                self.onDiagnostic?("raw TCP read failed generation=\(generation) error=\(error.localizedDescription); FAIL CLOSED, no reconnect loop")
                self.onPhase?("FAILED_SAFE")
                self.onStatus?("Live map transport failed — Navigation remains active", false)
                return
            }
            if complete {
                self.onDiagnostic?("raw TCP EOF generation=\(generation); FAIL CLOSED, no reconnect loop")
                self.onPhase?("FAILED_SAFE")
                self.onStatus?("Live map transport ended — Navigation remains active", false)
                return
            }
            self.receiveRawBytes(connection, generation: generation)
        }
    }

    private func processNAL(_ nal: Data, generation: Int) {
        let accepted = sanitizer.process(nal)

        // v24.20: a single frame_num jump is diagnostic evidence, not a hard
        // recovery trigger. With the v8.34 hard-bounded lossless mirror, normal operation should
        // be byte-continuous; if a jump is ever observed, keep feeding the validated
        // frame and let repeated VideoToolbox codecBadDataErr (-8969) prove whether
        // the decode epoch is actually unusable. This avoids manufacturing a long
        // WAITING_FRESH_IDR outage from one continuity observation.
        if let continuityWarning = sanitizer.takeContinuityBreakReason() {
            onDiagnostic?("REFERENCE CONTINUITY WARNING generation=\(generation): \(continuityWarning); frame forwarded, decoder remains authoritative")
        }

        if let accepted {
            if lifecyclePaused {
                if accepted.kind == .sps || accepted.kind == .pps {
                    onDiagnostic?("Lifecycle-paused filter accepted \(accepted.kind); decoder feed intentionally gated")
                }
                return
            }
            if accepted.kind == .idr, waitingForFreshLiveIDRAfterRejectedAnchor {
                waitingForFreshLiveIDRAfterRejectedAnchor = false
                onPhase?("DECODER_BOOTSTRAP")
                onStatus?("Fresh live IDR arrived after decoder recovery • rebuilding decoder…", true)
                onDiagnostic?("FRESH LIVE IDR accepted on preserved raw TCP")
            }
            decoder.consume(accepted.data)
            switch accepted.kind {
            case .sps: onDiagnostic?("iPhone filter accepted SPS • \(sanitizer.stats.summary)")
            case .pps: onDiagnostic?("iPhone filter accepted PPS • \(sanitizer.stats.summary)")
            case .idr:
                let count = sanitizer.stats.acceptedIDR
                if !firstAcceptedIDRForConnection {
                    firstAcceptedIDRForConnection = true
                    onPhase?("DECODER_BOOTSTRAP")
                    onStatus?("Validated IDR bootstrap received • starting decoder…", true)
                    onDiagnostic?("FIRST BOOTSTRAP IDR accepted for TCP generation=\(generation) • \(sanitizer.stats.summary)")
                } else if count <= 3 || count % 10 == 0 { onDiagnostic?("iPhone filter accepted IDR #\(count) • \(sanitizer.stats.summary)") }
            case .slice:
                let count = sanitizer.stats.acceptedSlices
                if count > 0, count % 1000 == 0 { onDiagnostic?("iPhone filter live slice milestone=\(count) • \(sanitizer.stats.summary)") }
            }
        }
    }

    private func receiveExactly(
        _ count: Int,
        from connection: NWConnection,
        generation: Int,
        accumulated: Data = Data(),
        completion: @escaping (Data) -> Void
    ) {
        guard running, self.connection === connection, self.connectionGeneration == generation else { return }
        let remaining = count - accumulated.count
        guard remaining > 0 else { completion(accumulated); return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection, self.running, self.connection === connection, self.connectionGeneration == generation else { return }
            var next = accumulated
            if let data, !data.isEmpty {
                self.onBytes?(data.count)
                next.append(data)
            }
            if let error {
                self.onDiagnostic?("TCP read failed generation=\(generation) wanted=\(count) have=\(next.count) error=\(error.localizedDescription)")
                self.scheduleReconnect(reason: "TCP read error", delay: 1.0)
                return
            }
            if complete, next.count < count {
                self.onDiagnostic?("TCP read EOF generation=\(generation) wanted=\(count) have=\(next.count)")
                self.scheduleReconnect(reason: "TCP EOF", delay: 1.0)
                return
            }
            if next.count == count {
                completion(next)
            } else {
                self.receiveExactly(count, from: connection, generation: generation, accumulated: next, completion: completion)
            }
        }
    }

    private func emitSanitizerStats(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || lastStatsEmitUptime == 0 || now - lastStatsEmitUptime >= 1.0 else { return }
        lastStatsEmitUptime = now
        onSanitizerStats?(sanitizer.stats)
        onDecoderState?(decoder.stateSummary)
    }

    /// Publish decoder diagnostics immediately after an explicit recovery/flush
    /// action. This bypasses the one-second sanitizer-stats throttle so the
    /// MainVideo preflight reflects the new VideoToolbox state right away.
    private func emitDecoderState() {
        onDecoderState?(decoder.stateSummary)
    }

    private func closeCurrentConnection() {
        waitingDeadlineWorkItem?.cancel(); waitingDeadlineWorkItem = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        decoder.discardPendingAccessUnit()
        emitSanitizerStats(force: true)
    }

    private func scheduleReconnect(reason: String, delay: TimeInterval = 1.0) {
        guard running else { return }
        closeCurrentConnection()
        reconnectWorkItem?.cancel()
        onPhase?("RECONNECT_DELAY")
        onStatus?("U2W H.264 reconnecting at live edge…", false)
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            self.onDiagnostic?("TCP reconnect firing reason=\(reason) delay=\(String(format: "%.2f", delay))s")
            self.openConnection()
        }
        reconnectWorkItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

/// Incremental Annex-B splitter. It keeps the final incomplete NAL until the
/// next start code arrives, so arbitrary HTTP/TCP chunk boundaries are safe.
private final class AnnexBH264Parser {
    private var buffer = Data()

    func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    func append(_ data: Data) -> [Data] {
        guard !data.isEmpty else { return [] }
        buffer.append(data)

        let starts = startCodes(in: buffer)
        guard starts.count >= 2 else {
            if buffer.count > 4 * 1024 * 1024 {
                buffer.removeAll(keepingCapacity: true)
            }
            return []
        }

        var output: [Data] = []
        for index in 0..<(starts.count - 1) {
            let current = starts[index]
            let next = starts[index + 1]
            let payloadStart = current.offset + current.length
            guard next.offset > payloadStart else { continue }
            let candidateLength = next.offset - payloadStart
            // Field data shows false Annex-B markers can delimit very large chunks.
            // Skip them without copying megabytes into a temporary Data object.
            guard candidateLength <= 512 * 1024 else { continue }
            var nal = buffer.subdata(in: payloadStart..<next.offset)
            // Annex-B permits trailing_zero_8bits before the next start code.
            // VideoToolbox parameter-set creation is less forgiving than ffmpeg,
            // so keep those transport/alignment zeros out of the NAL payload.
            while nal.last == 0 { nal.removeLast() }
            guard !nal.isEmpty else { continue }
            output.append(nal)
        }

        let keepFrom = starts[starts.count - 1].offset
        if keepFrom > 0 {
            buffer.removeSubrange(0..<keepFrom)
        }
        return output
    }

    private func startCodes(in data: Data) -> [(offset: Int, length: Int)] {
        data.withUnsafeBytes { raw -> [(Int, Int)] in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return [] }
            let count = raw.count
            var result: [(Int, Int)] = []
            var i = 0
            while i + 3 < count {
                if base[i] == 0, base[i + 1] == 0, base[i + 2] == 0, base[i + 3] == 1 {
                    result.append((i, 4))
                    i += 4
                } else if base[i] == 0, base[i + 1] == 0, base[i + 2] == 1 {
                    result.append((i, 3))
                    i += 3
                } else {
                    i += 1
                }
            }
            return result
        }
    }
}

/// Low-latency H.264 decoder.
///
/// v90.35.3.12 submitted every slice NAL as if it were a complete frame and
/// requested asynchronous VideoToolbox decompression. Multi-slice pictures can
/// therefore poison the decoder, while a fast producer can build a large async
/// backlog that later appears as a burst of stale frames. This decoder instead:
/// - groups slices into one H.264 access unit (AUD and first_mb_in_slice aware),
/// - submits one CMSampleBuffer per picture,
/// - decodes synchronously so VideoToolbox cannot accumulate a hidden queue,
/// - tolerates isolated bad access units without forcing an IDR reset,
/// - requires a fresh IDR only after an actual decoder/session rebuild, and
/// - publishes at most 15 images/s while always replacing the latest mailbox.
private final class H264VideoToolboxDecoder {
    // VideoToolbox reports kVTInvalidSessionErr as -12903. Keep a local OSStatus
    // literal so the recovery path is independent of SDK symbol-import spelling.
    private static let invalidSessionStatus: OSStatus = -12903
    // VideoToolbox/CodecServices codecBadDataErr observed in the 2026-09-23 field run.
    private static let codecBadDataStatus: OSStatus = -8969

    var onFrame: ((UIImage) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onRecoveryNeeded: ((String) -> Void)?

    // Candidate parameter sets are staged separately from the accepted pair.
    // A malformed/partial SPS/PPS must never replace the last-known-good decoder
    // state. This directly addresses the field loop where one bad candidate left
    // CMVideoFormatDescriptionCreateFromH264ParameterSets returning -12712 on every
    // 3-second reconnect.
    private var activeSPS: Data?
    private var activePPS: Data?
    private var pendingSPS: Data?
    private var pendingPPS: Data?
    private var lastRejectedParameterSetSignature = ""
    private var formatDescription: CMVideoFormatDescription?
    private var decompressionSession: VTDecompressionSession?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    private var pendingAccessUnit: [Data] = []
    private var pendingHasVCL = false
    private var needsIDR = true
    private var submittedAccessUnits = 0
    private var totalDecodeErrors = 0
    private var consecutiveDecodeErrors = 0
    private let consecutiveErrorRebuildThreshold = 5
    private var rebuildAtNextIDR = false
    private var lastDecodeStatus: OSStatus = noErr
    private var outputCallbackErrors = 0
    private var outputCallbackFrames = 0
    private var imageConversionErrors = 0
    private var lastOutputCallbackStatus: OSStatus = noErr
    private var hardRecoveryCount = 0
    private var recoveryRequestPending = false

    private let publishLock = NSLock()
    private var lastPublishedUptime: TimeInterval = 0
    private let minimumPublishInterval: TimeInterval = 1.0 / 15.0

    func reset() {
        discardPendingAccessUnit()
        if let decompressionSession {
            VTDecompressionSessionInvalidate(decompressionSession)
        }
        decompressionSession = nil
        formatDescription = nil
        activeSPS = nil
        activePPS = nil
        pendingSPS = nil
        pendingPPS = nil
        lastRejectedParameterSetSignature = ""
        needsIDR = true
        submittedAccessUnits = 0
        totalDecodeErrors = 0
        consecutiveDecodeErrors = 0
        rebuildAtNextIDR = false
        lastDecodeStatus = noErr
        outputCallbackErrors = 0
        outputCallbackFrames = 0
        imageConversionErrors = 0
        lastOutputCallbackStatus = noErr
        hardRecoveryCount = 0
        recoveryRequestPending = false
        publishLock.lock()
        lastPublishedUptime = 0
        publishLock.unlock()
    }

    /// iOS can invalidate VideoToolbox sessions across scene/background transitions.
    /// Preserve the last validated SPS/PPS but intentionally retire the VT session;
    /// the worker keeps TCP/Annex-B flowing and requests a fresh IDR only after the
    /// app has returned to a stable foreground state.
    func suspendForLifecycle(reason: String) {
        discardPendingAccessUnit()
        if let decompressionSession {
            VTDecompressionSessionInvalidate(decompressionSession)
        }
        decompressionSession = nil
        formatDescription = nil
        pendingSPS = nil
        pendingPPS = nil
        needsIDR = true
        rebuildAtNextIDR = false
        consecutiveDecodeErrors = 0
        recoveryRequestPending = false
        lastDecodeStatus = noErr
        lastOutputCallbackStatus = noErr
        onDiagnostic?("Decoder lifecycle suspend reason=\(reason); active SPS/PPS preserved, VT session invalidated")
    }

    /// A v8.17 transport reconnect can begin at an arbitrary raw position. Keep
    /// any already-accepted VideoToolbox session alive until a replacement pair
    /// has actually been validated and a new session has been created.
    func prepareForStreamRestart() {
        discardPendingAccessUnit()
        pendingSPS = nil
        pendingPPS = nil
        needsIDR = true
        submittedAccessUnits = 0
        totalDecodeErrors = 0
        consecutiveDecodeErrors = 0
        rebuildAtNextIDR = false
        lastDecodeStatus = noErr
        outputCallbackErrors = 0
        outputCallbackFrames = 0
        imageConversionErrors = 0
        lastOutputCallbackStatus = noErr
        recoveryRequestPending = false
    }

    var stateSummary: String {
        let session = decompressionSession == nil ? "none" : "ready"
        return "session=\(session) • needsIDR=\(needsIDR ? 1 : 0) • rebuildOnIDR=\(rebuildAtNextIDR ? 1 : 0) • recoveryPending=\(recoveryRequestPending ? 1 : 0) • recoveries=\(hardRecoveryCount) • AU=\(submittedAccessUnits) • errors=\(totalDecodeErrors)/\(consecutiveDecodeErrors) • outputs=\(outputCallbackFrames) • outputErr=\(outputCallbackErrors) • imageErr=\(imageConversionErrors) • lastStatus=\(lastDecodeStatus) • outputStatus=\(lastOutputCallbackStatus)"
    }

    func discardPendingAccessUnit() {
        pendingAccessUnit.removeAll(keepingCapacity: true)
        pendingHasVCL = false
    }

    func consume(_ nal: Data) {
        guard let first = nal.first else { return }
        let type = first & 0x1F

        switch type {
        case 7: // SPS
            flushAccessUnit()
            stageParameterSet(nal, type: 7)
        case 8: // PPS
            flushAccessUnit()
            stageParameterSet(nal, type: 8)
        case 9: // Access Unit Delimiter
            flushAccessUnit()
        case 6: // SEI normally belongs to the picture that follows it.
            if pendingHasVCL {
                flushAccessUnit()
            }
            pendingAccessUnit.append(nal)
        case 1, 5: // non-IDR / IDR VCL
            if pendingHasVCL, Self.firstMbInSliceIsZero(nal) == true {
                flushAccessUnit()
            }
            pendingAccessUnit.append(nal)
            pendingHasVCL = true
        default:
            break
        }
    }

    private func flushAccessUnit() {
        guard pendingHasVCL else {
            pendingAccessUnit.removeAll(keepingCapacity: true)
            return
        }
        let accessUnit = pendingAccessUnit
        pendingAccessUnit.removeAll(keepingCapacity: true)
        pendingHasVCL = false
        decodeAccessUnit(accessUnit)
    }

    private func stageParameterSet(_ rawNAL: Data, type: UInt8) {
        guard let nal = Self.sanitizedParameterSet(rawNAL, expectedType: type) else {
            onDiagnostic?("Rejected malformed H.264 parameter set type=\(type) bytes=\(rawNAL.count)")
            return
        }

        if type == 7 {
            if nal == activeSPS {
                pendingSPS = nil
                return
            }
            pendingSPS = nal
        } else {
            if nal == activePPS {
                pendingPPS = nil
                return
            }
            pendingPPS = nal
        }
        promoteValidParameterSetPairIfPossible()
    }

    private func promoteValidParameterSetPairIfPossible() {
        var candidates: [(Data, Data, String)] = []
        if let pendingSPS, let pendingPPS {
            candidates.append((pendingSPS, pendingPPS, "pending+pending"))
        }
        if let pendingSPS, let activePPS {
            candidates.append((pendingSPS, activePPS, "pendingSPS+activePPS"))
        }
        if let activeSPS, let pendingPPS {
            candidates.append((activeSPS, pendingPPS, "activeSPS+pendingPPS"))
        }

        // The first decoder session needs both parameter sets from the stream.
        // Once a good pair exists, one side may legitimately remain unchanged.
        guard !candidates.isEmpty else { return }

        for (candidateSPS, candidatePPS, source) in candidates {
            let signature = "\(Self.parameterSetSignature(candidateSPS))/\(Self.parameterSetSignature(candidatePPS))"
            var description: CMVideoFormatDescription?
            let status = Self.createFormatDescription(
                sps: candidateSPS,
                pps: candidatePPS,
                output: &description
            )
            guard status == noErr, let videoDescription = description else {
                if signature != lastRejectedParameterSetSignature {
                    lastRejectedParameterSetSignature = signature
                    onDiagnostic?(
                        "Rejected SPS/PPS candidate status=\(status) source=\(source) \(signature); preserving last-known-good decoder"
                    )
                }
                continue
            }

            var callback = VTDecompressionOutputCallbackRecord(
                decompressionOutputCallback: { outputRefCon, _, status, _, imageBuffer, _, _ in
                    guard let outputRefCon else { return }
                    let decoder = Unmanaged<H264VideoToolboxDecoder>
                        .fromOpaque(outputRefCon)
                        .takeUnretainedValue()
                    decoder.handleOutputCallback(status: status, imageBuffer: imageBuffer)
                },
                decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
            )

            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA)
            ]
            // v90.35.3.24: prefer the software VideoToolbox decoder for this tiny
            // 800×480 navigation surface. Field logs correlated hardware-session
            // invalidation (-12903) with iOS lifecycle transitions; software decode
            // avoids losing a sparse H.264 reference chain merely because the app
            // temporarily backgrounds while CarPlay remains active.
            let decoderSpecification: [CFString: Any] = [
                kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: NSNumber(value: false)
            ]
            var candidateSession: VTDecompressionSession?
            let createStatus = VTDecompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                formatDescription: videoDescription,
                decoderSpecification: decoderSpecification as CFDictionary,
                imageBufferAttributes: attributes as CFDictionary,
                outputCallback: &callback,
                decompressionSessionOut: &candidateSession
            )
            guard createStatus == noErr, let candidateSession else {
                if signature != lastRejectedParameterSetSignature {
                    lastRejectedParameterSetSignature = signature
                    onDiagnostic?(
                        "Rejected SPS/PPS decoder session status=\(createStatus) source=\(source) \(signature); preserving last-known-good decoder"
                    )
                }
                continue
            }

            // This is a live navigation surface, not file playback. Ask
            // VideoToolbox to prioritize real-time decode/output and avoid
            // accumulating a hidden backlog when the app is under load. A
            // nonzero property status is diagnostic only; the session remains
            // usable and the normal stall watchdog still protects output.
            let realTimeStatus = VTSessionSetProperty(
                candidateSession,
                key: kVTDecompressionPropertyKey_RealTime,
                value: kCFBooleanTrue
            )
            if realTimeStatus != noErr {
                onDiagnostic?("VideoToolbox RealTime property status=\(realTimeStatus); continuing with decoder")
            }

            // Atomic promotion: only now retire the prior VideoToolbox session.
            let previousSession = decompressionSession
            decompressionSession = candidateSession
            formatDescription = videoDescription
            activeSPS = candidateSPS
            activePPS = candidatePPS
            if pendingSPS == candidateSPS { pendingSPS = nil }
            if pendingPPS == candidatePPS { pendingPPS = nil }
            lastRejectedParameterSetSignature = ""
            needsIDR = true
            if let previousSession {
                VTDecompressionSessionInvalidate(previousSession)
            }
            onDiagnostic?(
                "Decoder session ready source=\(source) \(signature); software-preferred=1; waiting for current IDR"
            )
            return
        }
    }

    private static func createFormatDescription(
        sps: Data,
        pps: Data,
        output: inout CMVideoFormatDescription?
    ) -> OSStatus {
        sps.withUnsafeBytes { spsRaw in
            pps.withUnsafeBytes { ppsRaw in
                guard
                    let spsBase = spsRaw.bindMemory(to: UInt8.self).baseAddress,
                    let ppsBase = ppsRaw.bindMemory(to: UInt8.self).baseAddress
                else { return -1 }

                var pointers: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                var sizes: [Int] = [sps.count, pps.count]
                return pointers.withUnsafeBufferPointer { pointerBuffer in
                    sizes.withUnsafeBufferPointer { sizeBuffer in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: pointerBuffer.baseAddress!,
                            parameterSetSizes: sizeBuffer.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &output
                        )
                    }
                }
            }
        }
    }

    private static func sanitizedParameterSet(_ rawNAL: Data, expectedType: UInt8) -> Data? {
        var nal = rawNAL

        // Be tolerant if a caller accidentally includes an Annex-B prefix.
        if nal.starts(with: [0, 0, 0, 1]) {
            nal.removeFirst(4)
        } else if nal.starts(with: [0, 0, 1]) {
            nal.removeFirst(3)
        }
        while nal.last == 0 { nal.removeLast() }

        guard let first = nal.first,
              first & 0x80 == 0,
              first & 0x1F == expectedType else { return nil }
        // Real CarPlay SPS/PPS are tiny. The generous bound rejects accidental
        // multi-NAL/garbage candidates without constraining legitimate profiles.
        guard nal.count >= 2, nal.count <= 256 else { return nil }
        return nal
    }

    private static func parameterSetSignature(_ data: Data) -> String {
        let prefix = data.prefix(8).map { String(format: "%02X", $0) }.joined()
        let suffix = data.suffix(min(4, data.count)).map { String(format: "%02X", $0) }.joined()
        return "len=\(data.count),head=\(prefix),tail=\(suffix)"
    }

    private func decodeAccessUnit(_ nals: [Data]) {
        let hasIDR = nals.contains { ($0.first ?? 0) & 0x1F == 5 }

        // A fatal/output-stall recovery request is handled on the worker's serial
        // queue. Do not keep feeding the session while that reset is pending.
        if recoveryRequestPending { return }

        // If a background/lifecycle transition caused decoder creation to fail,
        // retry creation from the last validated parameter-set pair when a clean
        // IDR is actually in hand.
        if hasIDR, decompressionSession == nil, let activeSPS, let activePPS {
            pendingSPS = activeSPS
            pendingPPS = activePPS
            onDiagnostic?("Validated IDR arrived with no decoder session; recreating from last-known-good SPS/PPS")
            promoteValidParameterSetPairIfPossible()
        }

        // Never destroy a decoder that may still recover while only P-frames are
        // available. Five consecutive errors merely arm a rebuild. The actual
        // VideoToolbox session swap happens atomically when a validated *future*
        // IDR is already in hand, so recovery can never create an IDR drought.
        if hasIDR, rebuildAtNextIDR, let activeSPS, let activePPS {
            pendingSPS = activeSPS
            pendingPPS = activePPS
            onDiagnostic?("Fresh IDR arrived with rebuild armed; atomically rebuilding decoder now")
            promoteValidParameterSetPairIfPossible()
            rebuildAtNextIDR = false
        }

        guard let decompressionSession, let formatDescription else { return }
        if needsIDR {
            guard hasIDR else { return }
            needsIDR = false
        }

        var avcc = Data()
        avcc.reserveCapacity(nals.reduce(0) { $0 + $1.count + 4 })
        for nal in nals {
            var length = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &length) { avcc.append(contentsOf: $0) }
            avcc.append(nal)
        }
        guard !avcc.isEmpty else { return }

        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avcc.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avcc.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let blockBuffer else {
            onDiagnostic?("CMBlockBuffer create failed status=\(blockStatus)")
            return
        }

        let copyStatus: OSStatus = avcc.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: avcc.count
            )
        }
        guard copyStatus == noErr else {
            onDiagnostic?("CMBlockBuffer copy failed status=\(copyStatus)")
            return
        }

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = avcc.count
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            onDiagnostic?("CMSampleBuffer create failed status=\(sampleStatus)")
            return
        }

        submittedAccessUnits += 1
        var infoFlags = VTDecodeInfoFlags()
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            decompressionSession,
            sampleBuffer: sampleBuffer,
            flags: VTDecodeFrameFlags(rawValue: 0),
            frameRefcon: nil,
            infoFlagsOut: &infoFlags
        )
        lastDecodeStatus = decodeStatus

        if decodeStatus != noErr {
            totalDecodeErrors += 1
            consecutiveDecodeErrors += 1

            if decodeStatus == Self.codecBadDataStatus {
                onDiagnostic?(
                    "VideoToolbox codecBadDataErr status=\(decodeStatus) au=\(submittedAccessUnits) consecutive=\(consecutiveDecodeErrors); dropping this AU"
                )
                if consecutiveDecodeErrors >= 3 {
                    // The 2026-10-01 drive showed that merely arming an IDR swap can
                    // leave the session poisoned for thousands of access units.
                    // Escalate bounded -8969 bursts to the worker's fresh-epoch
                    // quarantine path while preserving the healthy TCP connection.
                    requestHardRecovery(reason: "\(consecutiveDecodeErrors) consecutive codecBadDataErr (-8969) submissions")
                }
                return
            }

            if decodeStatus == Self.invalidSessionStatus {
                onDiagnostic?(
                    "FATAL VideoToolbox invalid session status=\(decodeStatus) au=\(submittedAccessUnits); immediate decoder reset requested; worker applies bounded transport recovery"
                )
                requestHardRecovery(reason: "kVTInvalidSessionErr (-12903) from VTDecompressionSessionDecodeFrame")
                return
            }

            onDiagnostic?(
                "Decode error status=\(decodeStatus) au=\(submittedAccessUnits) total=\(totalDecodeErrors) consecutive=\(consecutiveDecodeErrors)"
            )

            if consecutiveDecodeErrors >= consecutiveErrorRebuildThreshold,
               activeSPS != nil, activePPS != nil, !rebuildAtNextIDR {
                // Non-fatal bad access units can still recover on the existing
                // reference chain. Arm a safe swap at a future validated IDR.
                rebuildAtNextIDR = true
                onDiagnostic?(
                    "Decoder rebuild ARMED after \(consecutiveErrorRebuildThreshold) non-fatal consecutive errors; existing session preserved until future IDR"
                )
            }
        } else {
            if consecutiveDecodeErrors > 0 {
                onDiagnostic?("Decoder recovered after \(consecutiveDecodeErrors) consecutive error(s) without IDR reset")
            }
            // A successful compressed-AU submission is NOT proof of decoder recovery.
            // Keep any armed rebuild until VideoToolbox produces a real image callback.
            consecutiveDecodeErrors = 0
            if submittedAccessUnits == 1 || submittedAccessUnits % 300 == 0 {
                onDiagnostic?("Decoded access unit #\(submittedAccessUnits) nals=\(nals.count)")
            }
        }
    }

    private func handleOutputCallback(status: OSStatus, imageBuffer: CVImageBuffer?) {
        lastOutputCallbackStatus = status

        guard status == noErr, let imageBuffer else {
            outputCallbackErrors += 1
            if outputCallbackErrors <= 5 || outputCallbackErrors % 100 == 0 {
                onDiagnostic?(
                    "VideoToolbox output callback failure status=\(status) image=\(imageBuffer == nil ? 0 : 1) count=\(outputCallbackErrors)"
                )
            }
            if status == Self.codecBadDataStatus {
                if outputCallbackErrors >= 3 {
                    // Output-callback -8969 was the dominant field failure: raw
                    // bytes remained live while 4,111 callbacks failed.  Do not
                    // keep feeding that poisoned epoch. The worker recognizes the
                    // codecBadDataErr reason and performs the existing fresh
                    // SPS/PPS/IDR quarantine without reconnecting TCP.
                    requestHardRecovery(reason: "\(outputCallbackErrors) codecBadDataErr (-8969) output callback failures")
                }
            } else if status == Self.invalidSessionStatus {
                requestHardRecovery(reason: "kVTInvalidSessionErr (-12903) from VideoToolbox output callback")
            } else if outputCallbackErrors >= 3 {
                armRebuildAtNextIDR(reason: "\(outputCallbackErrors) nonfatal VideoToolbox output callback failures status=\(status)")
            }
            return
        }

        if outputCallbackErrors > 0 {
            onDiagnostic?("VideoToolbox output callback recovered after \(outputCallbackErrors) failure(s)")
        }
        outputCallbackErrors = 0
        if rebuildAtNextIDR {
            rebuildAtNextIDR = false
            onDiagnostic?("Decoder recovery CONFIRMED by successful image callback; armed future-IDR rebuild cancelled")
        }
        consecutiveDecodeErrors = 0
        outputCallbackFrames += 1
        lastOutputCallbackStatus = noErr
        publish(imageBuffer)
    }

    func armRebuildAtNextIDR(reason: String) {
        guard decompressionSession != nil, activeSPS != nil, activePPS != nil else {
            onDiagnostic?("Future-IDR rebuild requested but decoder/parameter-set pair is not established; leaving current bootstrap state unchanged reason=\(reason)")
            return
        }
        if !rebuildAtNextIDR {
            rebuildAtNextIDR = true
            onDiagnostic?("Decoder rebuild ARMED without destroying current session reason=\(reason); swap occurs only when a validated future IDR is already in hand")
        }
    }

    private func requestHardRecovery(reason: String) {
        guard !recoveryRequestPending else { return }
        recoveryRequestPending = true
        onDiagnostic?("Decoder hard recovery requested reason=\(reason)")
        onRecoveryNeeded?(reason)
    }

    func hardRecoverAwaitingFreshCodecEpoch(reason: String) {
        discardPendingAccessUnit()

        if let decompressionSession {
            VTDecompressionSessionInvalidate(decompressionSession)
        }
        decompressionSession = nil
        formatDescription = nil
        activeSPS = nil
        activePPS = nil
        pendingSPS = nil
        pendingPPS = nil
        lastRejectedParameterSetSignature = ""
        needsIDR = true
        rebuildAtNextIDR = false
        consecutiveDecodeErrors = 0
        outputCallbackErrors = 0
        lastDecodeStatus = noErr
        lastOutputCallbackStatus = noErr
        recoveryRequestPending = false
        hardRecoveryCount += 1
        onDiagnostic?(
            "Decoder fresh-epoch recovery #\(hardRecoveryCount) complete reason=\(reason); discarded prior SPS/PPS and waiting for fresh codec epoch"
        )
    }

    func hardRecoverAwaitingIDR(reason: String) {
        discardPendingAccessUnit()

        if let decompressionSession {
            VTDecompressionSessionInvalidate(decompressionSession)
        }
        decompressionSession = nil
        formatDescription = nil
        pendingSPS = activeSPS
        pendingPPS = activePPS
        needsIDR = true
        rebuildAtNextIDR = false
        consecutiveDecodeErrors = 0
        outputCallbackErrors = 0
        lastDecodeStatus = noErr
        lastOutputCallbackStatus = noErr
        recoveryRequestPending = false
        hardRecoveryCount += 1

        if activeSPS != nil, activePPS != nil {
            promoteValidParameterSetPairIfPossible()
        }
        onDiagnostic?(
            "Decoder hard recovery #\(hardRecoveryCount) complete reason=\(reason); waiting for validated IDR"
        )
    }

    func finishDelayedFramesForStallProbe() {
        guard let decompressionSession else { return }
        let finishStatus = VTDecompressionSessionFinishDelayedFrames(decompressionSession)
        let waitStatus = VTDecompressionSessionWaitForAsynchronousFrames(decompressionSession)
        onDiagnostic?(
            "Decoder stall soft-flush finishStatus=\(finishStatus) waitStatus=\(waitStatus)"
        )
    }

    private func publish(_ pixelBuffer: CVImageBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        publishLock.lock()
        let shouldPublish = lastPublishedUptime == 0 || now - lastPublishedUptime >= minimumPublishInterval
        if shouldPublish {
            lastPublishedUptime = now
        }
        publishLock.unlock()
        guard shouldPublish else { return }

        let image = CIImage(cvImageBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            imageConversionErrors += 1
            if imageConversionErrors <= 3 || imageConversionErrors % 100 == 0 {
                onDiagnostic?("Decoded pixel buffer could not be converted to CGImage count=\(imageConversionErrors) outputCallbacks=\(outputCallbackFrames)")
            }
            return
        }
        onFrame?(UIImage(cgImage: cgImage))
    }

    /// H.264 slice_header begins with first_mb_in_slice, an unsigned Exp-Golomb
    /// value. A value of zero marks the first slice of a new picture. We remove
    /// emulation-prevention bytes before reading the RBSP bits.
    private static func firstMbInSliceIsZero(_ nal: Data) -> Bool? {
        guard nal.count > 1 else { return nil }
        let payload = Array(nal.dropFirst())
        var rbsp: [UInt8] = []
        rbsp.reserveCapacity(payload.count)
        var zeroCount = 0
        for byte in payload {
            if zeroCount >= 2, byte == 0x03 {
                zeroCount = 0
                continue
            }
            rbsp.append(byte)
            if byte == 0 {
                zeroCount += 1
            } else {
                zeroCount = 0
            }
        }
        guard let value = readUnsignedExpGolomb(rbsp) else { return nil }
        return value == 0
    }

    private static func readUnsignedExpGolomb(_ bytes: [UInt8]) -> UInt32? {
        var bitIndex = 0
        var leadingZeroBits = 0

        func readBit() -> UInt8? {
            guard bitIndex < bytes.count * 8 else { return nil }
            let byte = bytes[bitIndex / 8]
            let shift = 7 - (bitIndex % 8)
            bitIndex += 1
            return (byte >> shift) & 1
        }

        var sawStopBit = false
        while let bit = readBit() {
            if bit == 1 {
                sawStopBit = true
                break
            }
            leadingZeroBits += 1
            if leadingZeroBits > 31 { return nil }
        }
        guard sawStopBit else { return nil }
        if leadingZeroBits == 0 { return 0 }

        var suffix: UInt32 = 0
        for _ in 0..<leadingZeroBits {
            guard let bit = readBit() else { return nil }
            suffix = (suffix << 1) | UInt32(bit)
        }
        return ((UInt32(1) << UInt32(leadingZeroBits)) - 1) + suffix
    }
}

import Foundation
import Observation
import UIKit
import VideoToolbox
import CoreMedia
import CoreImage
import Network

/// v90.35.3.23 MainVideo client for U2W v8.23.
///
/// Video no longer travels through a long-lived Boa CGI or through a cache file
/// that is truncated underneath an active reader.  The adapter-side relay tails
/// the stable v8.11 mirror and publishes only the live edge as length-framed H.264
/// NAL units on TCP/15332. A new iPhone connection waits for the next naturally
/// arriving live IDR; there is no historical GOP replay or catch-up burst. The
/// connection is prepared before navigation and remains warm for the whole car session.
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
    // source-compatible. In v8.23 it describes the dedicated live-IDR TCP relay.
    private(set) var adapterCacheSummary = "H.264 relay not checked"
    private(set) var transportPhase = "IDLE"
    private(set) var lastFrameAgeSeconds: Double?
    private(set) var adapterRelayConfirmedRunning = false
    private(set) var decoderSummary = "session=none • needsIDR=1 • errors=0"

    private let preflightRequiredContinuity: TimeInterval = 20.0

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
        if preflightReady { return "LIVE • 20s continuity verified" }
        if transportPhase == "LIVE", let preflightStableSince {
            let elapsed = min(preflightRequiredContinuity, max(0, Date().timeIntervalSince(preflightStableSince)))
            return "LIVE • validating continuity \(Int(elapsed))/\(Int(preflightRequiredContinuity))s"
        }
        if transportPhase == "DECODER_RECOVERY" { return "Decoder recovery • waiting for clean live IDR" }
        if transportPhase == "WAITING_LIVE_IDR" { return "Connected • waiting for next live IDR" }
        if transportPhase == "WAITING_RELAY" { return "Waiting for U2W v8.23 relay" }
        if transportPhase == "TCP_WAITING" { return "TCP waiting — automatic retry armed" }
        if transportPhase == "DECODER_BOOTSTRAP" { return "Live IDR received • decoder starting" }
        return "Not ready • \(transportPhase)"
    }

    var sanitizerSummary: String {
        "raw \(rawNALCount) • valid \(acceptedNALCount) • rejected \(rejectedNALCount) • " +
        "SPS \(acceptedSPSCount) PPS \(acceptedPPSCount) IDR \(acceptedIDRCount) slices \(acceptedSliceCount)"
    }

    private let logger: LogManager
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
    private var networkMonitors: [String: NWPathMonitor] = [:]
    private var networkSignatures: [String: String] = [:]
    private var networkStatuses: [String: String] = [:]
    private let networkPathQueue = DispatchQueue(label: "HUD.MainVideo.NetworkPath")
    private let relayStartEndpoint = URL(string: "http://192.168.50.2/cgi-bin/u2wvideo-relay-start.cgi")!
    private let relayStatusEndpoint = URL(string: "http://192.168.50.2/cgi-bin/u2wvideo-relay-status.cgi")!

    private let decoderStaleFrameInterval: TimeInterval = 3.0
    private let sourceStaleInterval: TimeInterval = 15.0
    private let initialIDRWaitDiagnosticInterval: TimeInterval = 20.0
    private let sourceReconnectCooldown: TimeInterval = 15.0
    private let relayEnsureCooldown: TimeInterval = 5.0

    init(logger: LogManager) { self.logger = logger }

    func start(reason: String) {
        if running {
            if worker == nil {
                beginRelayBootstrapLoop(reason: "already running / \(reason)")
            }
            return
        }
        running = true
        status = "Preparing U2W v8.23 live-IDR relay…"
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
        lastSourceReconnectAt = nil
        lastRelayEnsureAt = nil
        adapterRelayConfirmedRunning = false
        rawNALCount = 0
        acceptedNALCount = 0
        rejectedNALCount = 0
        acceptedSPSCount = 0
        acceptedPPSCount = 0
        acceptedIDRCount = 0
        acceptedSliceCount = 0
        decoderSummary = "session=none • needsIDR=1 • errors=0"
        logger.log("U2W VIDEO", "Start reason=\(reason) architecture=v8.23-live-idr-tcp-15332 historicalGOPReplay=0 continuousPredecode=1 longLivedBoaVideo=0")
        startNetworkPathLogging()
        startFreshnessWatchdog()
        beginRelayBootstrapLoop(reason: reason)
    }

    private func beginRelayBootstrapLoop(reason: String) {
        bootstrapTask?.cancel()
        bootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var attempt = 0
            while self.running, !Task.isCancelled, self.worker == nil {
                attempt += 1
                self.transportPhase = "WAITING_RELAY"
                let ready = await self.ensureAdapterRelay(reason: "bootstrap #\(attempt) / \(reason)")
                guard self.running, !Task.isCancelled else { return }
                if ready {
                    self.logger.log("MAINVIDEO PREFLIGHT", "relay confirmed RUNNING before TCP open attempt=\(attempt)")
                    self.startWorker(reason: "relay confirmed / \(reason)")
                    return
                }
                self.status = "Waiting for U2W v8.23 relay…"
                self.logger.log("MAINVIDEO PREFLIGHT", "relay not ready attempt=\(attempt); TCP intentionally NOT opened")
                try? await Task.sleep(for: .seconds(2))
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
            let marker = fields["marker"] ?? "?"
            let relayVersion = fields["relay_version"] ?? "?"
            let clientState = fields["client_state"] ?? "?"
            let haveSPS = fields["have_sps"] ?? "?"
            let havePPS = fields["have_pps"] ?? "?"
            let idr = fields["idr"] ?? "?"
            let bootstraps = fields["client_live_bootstraps"] ?? "?"
            let sendFailures = fields["client_send_failures"] ?? "?"
            let sourceBytes = fields["source_bytes_low32"] ?? "?"
            let generationChanges = fields["source_generation_changes"] ?? "?"
            let droppedPreIDR = fields["pre_idr_slices_dropped"] ?? "?"
            let lastNAL = fields["last_nal_type"] ?? "?"
            adapterCacheSummary = "\(process) • \(clientState) • SPS \(haveSPS) PPS \(havePPS) • IDR \(idr) • boots \(bootstraps) • sendFail \(sendFailures) • src \(sourceBytes)B gen \(generationChanges) preIDRdrop \(droppedPreIDR) lastNAL \(lastNAL)"
            let ready = (200...299).contains(code) && process == "RUNNING" && marker == "YES" && relayVersion.contains("v8.23")
            adapterRelayConfirmedRunning = ready
            logger.log("U2W H264 RELAY", "status reason=\(reason) HTTP=\(code) ready=\(ready ? 1 : 0) version=\(relayVersion) \(adapterCacheSummary)")
            return ready
        } catch {
            adapterRelayConfirmedRunning = false
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
        worker.onPhase = { [weak self] phase in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.workerGeneration == generation else { return }
                self.transportPhase = phase
                self.logger.log("MAINVIDEO STATE", "phase=\(phase) generation=\(generation)")
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
                self.decoderSummary = summary
            }
        }
        worker.onDecoderRecovery = { [weak self] reason in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.workerGeneration == generation else { return }
                self.decoderRecoveryPending = true
                self.preflightStableSince = nil
                self.preflightPassLogged = false
                self.transportPhase = "DECODER_RECOVERY"
                self.status = "VideoToolbox recovery • waiting for clean live IDR"
                self.logger.log("U2W VIDEO RECOVERY", reason)
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
                        "PASS 20s continuous decode frames=\(self.frameCount) source=\(self.sourceSize) — parked validation passed"
                    )
                }

                if lastPreflightLogAt.map({ now.timeIntervalSince($0) >= 5.0 }) ?? true {
                    lastPreflightLogAt = now
                    let frameAge = self.lastFrameAgeSeconds.map { String(format: "%.1fs", $0) } ?? "none"
                    let byteAge = self.lastReceivedBytesAt.map { String(format: "%.1fs", now.timeIntervalSince($0)) } ?? "none"
                    self.logger.log("MAINVIDEO PREFLIGHT", "phase=\(self.transportPhase) ready=\(self.preflightReady ? 1 : 0) tcp=\(self.connected ? 1 : 0) bytes=\(self.receivedBytes) byteAge=\(byteAge) frames=\(self.frameCount) frameAge=\(frameAge) filter={\(self.sanitizerSummary)} decoder={\(self.decoderSummary)} relay={\(self.adapterCacheSummary)}")
                }

                if self.lastNetworkHeartbeatAt.map({ now.timeIntervalSince($0) >= 15.0 }) ?? true {
                    self.lastNetworkHeartbeatAt = now
                    self.logNetworkContext(reason: "15s live-IDR MainVideo heartbeat")
                    _ = await self.refreshAdapterRelayStatus(reason: "15s MainVideo heartbeat")
                }

                guard self.worker != nil else {
                    if self.bootstrapTask == nil || self.bootstrapTask?.isCancelled == true {
                        self.beginRelayBootstrapLoop(reason: "watchdog worker missing")
                    }
                    continue
                }

                guard self.connected, let connectedAt = self.connectedAt else {
                    _ = await self.ensureAdapterRelay(reason: "TCP disconnected watchdog")
                    continue
                }

                let connectedAge = now.timeIntervalSince(connectedAt)
                let frameAge = self.lastDecodedFrameAt.map { now.timeIntervalSince($0) } ?? connectedAge
                let byteAge = self.lastReceivedBytesAt.map { now.timeIntervalSince($0) } ?? .infinity
                let bytesAreFresh = byteAge < 2.0

                // While the v8.23 relay is waiting for the next *live* IDR, silence is
                // expected. Do not reconnect and restart the wait window. Status/logs
                // make the wait visible to the parked preflight instead.
                if self.transportPhase == "WAITING_LIVE_IDR", self.receivedBytes <= 8 {
                    if connectedAge >= self.initialIDRWaitDiagnosticInterval,
                       self.lastDecoderStaleDiagnosticAt.map({ now.timeIntervalSince($0) >= self.initialIDRWaitDiagnosticInterval }) ?? true {
                        self.lastDecoderStaleDiagnosticAt = now
                        self.logger.log("U2W VIDEO WATCH", "TCP healthy but relay still waiting for next live IDR connectedAge=\(String(format: "%.1f", connectedAge))s; no reconnect performed")
                        _ = await self.refreshAdapterRelayStatus(reason: "waiting live IDR")
                    }
                    continue
                }

                // First-stage recovery for a live source whose output callback has
                // gone quiet: ask VideoToolbox to drain any delayed/asynchronous
                // work without destroying its reference chain. If this produces a
                // frame, onFrame resets the marker and normal decode continues.
                if bytesAreFresh, frameAge >= 1.5, frameAge < self.decoderStaleFrameInterval,
                   self.lastDecoderSoftFlushAt == nil {
                    self.lastDecoderSoftFlushAt = now
                    self.logger.log(
                        "U2W VIDEO WATCH",
                        "NALs fresh but decoded output age=\(String(format: "%.1f", frameAge))s; soft-flushing delayed VideoToolbox frames before hard recovery"
                    )
                    self.worker?.softFlushDecoder(reason: "fresh H.264 / stale output soft probe")
                }

                // v90.35.3.23 field evidence: the TCP/H.264 source can stay fresh while
                // VideoToolbox stops producing output for minutes, even while
                // VTDecompressionSessionDecodeFrame still returns noErr. Treat that as
                // a decoder-output stall, not a transport failure. Retire the decoder
                // session and wait for the next *validated* live IDR while preserving
                // the TCP stream and sanitizer state. This also catches output-callback
                // failures before they escalate to kVTInvalidSessionErr (-12903).
                if bytesAreFresh, frameAge >= self.decoderStaleFrameInterval {
                    if !self.decoderRecoveryPending {
                        self.decoderRecoveryPending = true
                        self.preflightStableSince = nil
                        self.preflightPassLogged = false
                        self.lastDecoderReseedAt = now
                        self.status = "H.264 source live — resetting stalled decoder"
                        self.transportPhase = "DECODER_RECOVERY"
                        self.logger.log(
                            "U2W VIDEO WATCH",
                            "NALs fresh byteAge=\(String(format: "%.1f", byteAge))s frameAge=\(String(format: "%.1f", frameAge))s; HARD decoder recovery, TCP preserved filter={\(self.sanitizerSummary)}"
                        )
                        self.worker?.recoverDecoderAtNextIDR(
                            reason: "fresh H.264 but no decoded frame for \(String(format: "%.1f", frameAge))s"
                        )
                    }
                    continue
                }

                guard self.receivedBytes > 8, !bytesAreFresh, byteAge >= self.sourceStaleInterval else { continue }
                let mayReconnect = self.lastSourceReconnectAt.map { now.timeIntervalSince($0) >= self.sourceReconnectCooldown } ?? true
                guard mayReconnect else { continue }
                self.lastSourceReconnectAt = now
                self.connected = false
                self.connectedAt = nil
                self.status = "U2W H.264 relay silent — reconnecting at next live IDR…"
                self.logger.log("U2W VIDEO WATCH", "TCP source silent byteAge=\(byteAge.isFinite ? String(format: "%.1f", byteAge) : "unknown")s; verify daemon then reconnect")
                _ = await self.ensureAdapterRelay(reason: "source silent")
                self.worker?.reconnectAtLiveEdge(reason: "source silent >=15s")
            }
        }
    }

    func applicationDidEnterBackground() {
        guard running else { return }
        backgroundedAt = Date()
        preflightStableSince = nil
        preflightPassLogged = false
        logger.log(
            "U2W VIDEO LIFECYCLE",
            "App entered background; TCP remains connected, but VideoToolbox hardware decode may be invalidated by iOS"
        )
    }

    func applicationDidBecomeActive() {
        guard running else { return }
        let now = Date()
        let backgroundDuration = backgroundedAt.map { now.timeIntervalSince($0) }
        backgroundedAt = nil

        let frameAge = lastDecodedFrameAt.map { now.timeIntervalSince($0) } ?? .infinity
        if let backgroundDuration, backgroundDuration >= 0.5, connected {
            decoderRecoveryPending = true
            preflightStableSince = nil
            preflightPassLogged = false
            transportPhase = "DECODER_RECOVERY"
            status = "Returned to foreground — refreshing VideoToolbox decoder"
            logger.log(
                "U2W VIDEO LIFECYCLE",
                "Foreground after \(String(format: "%.1f", backgroundDuration))s background; proactively recreating decoder, TCP preserved frameAge=\(frameAge.isFinite ? String(format: "%.1f", frameAge) : "none")s"
            )
            worker?.recoverDecoderAtNextIDR(reason: "app foreground after background transition")
        } else {
            logger.log(
                "U2W VIDEO LIFECYCLE",
                "App active; no forced decoder reset backgroundDuration=\(backgroundDuration.map { String(format: "%.1f", $0) } ?? "none") frameAge=\(frameAge.isFinite ? String(format: "%.1f", frameAge) : "none")"
            )
        }
    }

    func stop(reason: String) {
        guard running || worker != nil else { status = "U2W main video idle"; return }
        running = false
        freshnessTask?.cancel(); freshnessTask = nil
        bootstrapTask?.cancel(); bootstrapTask = nil
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
        logger.log("U2W VIDEO", "Stop reason=\(reason); dedicated TCP client closed")
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
    var onFrame: ((UIImage) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onSanitizerStats: ((H264MainVideoSanitizerStats) -> Void)?
    var onDecoderState: ((String) -> Void)?
    var onDecoderRecovery: ((String) -> Void)?

    private let sanitizer = H264MainVideoSanitizer()
    private let decoder = H264VideoToolboxDecoder()
    private let queue = DispatchQueue(label: "HUD.U2WMainVideo.TCP15332", qos: .userInitiated)
    private var connection: NWConnection?
    private var running = false
    private var reconnectWorkItem: DispatchWorkItem?
    private var waitingDeadlineWorkItem: DispatchWorkItem?
    private var lastStatsEmitUptime: TimeInterval = 0
    private var connectionGeneration = 0
    private var firstAcceptedIDRForConnection = false
    private let magic = Data("U2WH2642".utf8)
    private let maximumNALBytes = 512 * 1024

    init(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
        decoder.onFrame = { [weak self] image in self?.onFrame?(image) }
        decoder.onDiagnostic = { [weak self] message in self?.onDiagnostic?(message) }
        decoder.onRecoveryNeeded = { [weak self] reason in
            guard let self else { return }
            self.queue.async { [weak self] in
                guard let self, self.running else { return }
                self.decoder.hardRecoverAwaitingIDR(reason: reason)
                self.onPhase?("DECODER_RECOVERY")
                self.onStatus?("VideoToolbox recovery • waiting for clean live IDR", true)
                self.onDecoderRecovery?(reason)
                self.emitDecoderState()
            }
        }
    }

    func start() {
        guard !running else { return }
        running = true
        sanitizer.reset()
        decoder.reset()
        openConnection()
    }

    func stop() {
        running = false
        reconnectWorkItem?.cancel(); reconnectWorkItem = nil
        waitingDeadlineWorkItem?.cancel(); waitingDeadlineWorkItem = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel(); connection = nil
        sanitizer.reset()
        decoder.reset()
        onPhase?("IDLE")
    }

    func reconnectAtLiveEdge(reason: String) {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            self.onDiagnostic?("TCP live-edge reconnect requested reason=\(reason)")
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
            self.decoder.hardRecoverAwaitingIDR(reason: reason)
            self.onPhase?("DECODER_RECOVERY")
            self.onStatus?("VideoToolbox recovery • waiting for clean live IDR", true)
            self.onDecoderRecovery?(reason)
            self.emitDecoderState()
        }
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
        onStatus?("Opening U2W v8.23 live-IDR TCP/15332…", false)
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
                self.onStatus?("U2W H.264 TCP connected • checking v8.23 handshake", true)
                self.onDiagnostic?("TCP state generation=\(generation) READY")
                self.receiveHandshake(connection, generation: generation)
            case .failed(let error):
                self.onPhase?("RECONNECT_DELAY")
                self.onStatus?("U2W H.264 TCP failed: \(error.localizedDescription)", false)
                self.onDiagnostic?("TCP state generation=\(generation) FAILED error=\(error.localizedDescription)")
                self.scheduleReconnect(reason: "NWConnection failed", delay: 1.0)
            case .cancelled:
                self.onDiagnostic?("TCP state generation=\(generation) CANCELLED")
                if self.running { self.scheduleReconnect(reason: "NWConnection cancelled", delay: 1.0) }
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
        receiveExactly(magic.count, from: connection, generation: generation) { [weak self] data in
            guard let self else { return }
            guard data == self.magic else {
                let text = String(data: data, encoding: .ascii) ?? data.map { String(format: "%02X", $0) }.joined()
                self.onDiagnostic?("Invalid TCP relay magic={\(text)} expected=U2WH2642; reconnecting")
                self.scheduleReconnect(reason: "invalid relay magic", delay: 1.0)
                return
            }
            self.onPhase?("WAITING_LIVE_IDR")
            self.onStatus?("U2W v8.23 connected • waiting for next live IDR", true)
            self.onDiagnostic?("TCP relay handshake U2WH2642 accepted; historical GOP replay=0; waiting next live IDR")
            self.receiveLength(connection, generation: generation)
        }
    }

    private func receiveLength(_ connection: NWConnection, generation: Int) {
        receiveExactly(4, from: connection, generation: generation) { [weak self] header in
            guard let self else { return }
            let length = header.reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0, length <= self.maximumNALBytes else {
                self.onDiagnostic?("Invalid framed NAL length=\(length); reconnecting at next live IDR")
                self.scheduleReconnect(reason: "invalid NAL length", delay: 1.0)
                return
            }
            self.receiveNAL(length: length, connection: connection, generation: generation)
        }
    }

    private func receiveNAL(length: Int, connection: NWConnection, generation: Int) {
        receiveExactly(length, from: connection, generation: generation) { [weak self] nal in
            guard let self else { return }
            if let accepted = self.sanitizer.process(nal) {
                self.decoder.consume(accepted.data)
                switch accepted.kind {
                case .sps:
                    self.onDiagnostic?("iPhone filter accepted SPS • \(self.sanitizer.stats.summary)")
                case .pps:
                    self.onDiagnostic?("iPhone filter accepted PPS • \(self.sanitizer.stats.summary)")
                case .idr:
                    let count = self.sanitizer.stats.acceptedIDR
                    if !self.firstAcceptedIDRForConnection {
                        self.firstAcceptedIDRForConnection = true
                        self.onPhase?("DECODER_BOOTSTRAP")
                        self.onStatus?("Fresh live IDR received • starting decoder…", true)
                        self.onDiagnostic?("FIRST LIVE IDR accepted for TCP generation=\(generation) • \(self.sanitizer.stats.summary)")
                    } else if count <= 3 || count % 10 == 0 {
                        self.onDiagnostic?("iPhone filter accepted IDR #\(count) • \(self.sanitizer.stats.summary)")
                    }
                case .slice:
                    let count = self.sanitizer.stats.acceptedSlices
                    if count > 0, count % 1000 == 0 {
                        self.onDiagnostic?("iPhone filter live slice milestone=\(count) • \(self.sanitizer.stats.summary)")
                    }
                }
            }
            self.emitSanitizerStats()
            self.receiveLength(connection, generation: generation)
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
            var candidateSession: VTDecompressionSession?
            let createStatus = VTDecompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                formatDescription: videoDescription,
                decoderSpecification: nil,
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
                "Decoder session ready source=\(source) \(signature); waiting for current IDR"
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

            if decodeStatus == Self.invalidSessionStatus {
                onDiagnostic?(
                    "FATAL VideoToolbox invalid session status=\(decodeStatus) au=\(submittedAccessUnits); immediate decoder reset requested, TCP preserved"
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
            if rebuildAtNextIDR, !hasIDR {
                rebuildAtNextIDR = false
                onDiagnostic?("Decoder recovered on existing reference chain before next IDR; armed rebuild cancelled")
            }
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
            if status == Self.invalidSessionStatus {
                requestHardRecovery(reason: "kVTInvalidSessionErr (-12903) from VideoToolbox output callback")
            } else if outputCallbackErrors >= 3 {
                requestHardRecovery(reason: "3 consecutive VideoToolbox output callback failures status=\(status)")
            }
            return
        }

        if outputCallbackErrors > 0 {
            onDiagnostic?("VideoToolbox output callback recovered after \(outputCallbackErrors) failure(s)")
        }
        outputCallbackErrors = 0
        outputCallbackFrames += 1
        lastOutputCallbackStatus = noErr
        publish(imageBuffer)
    }

    private func requestHardRecovery(reason: String) {
        guard !recoveryRequestPending else { return }
        recoveryRequestPending = true
        onDiagnostic?("Decoder hard recovery requested reason=\(reason)")
        onRecoveryNeeded?(reason)
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

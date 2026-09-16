import Foundation
import Observation
import UIKit
import VideoToolbox
import CoreMedia
import CoreImage

/// v90.35.3.16 MainVideo client for the stable U2W v8.11 exporter + v8.17
/// latest-frame streamer.
///
/// Field captures prove fd33 contains genuine 800×480 CarPlay H.264 mixed with
/// unrelated bytes. The adapter therefore stays deliberately simple: it only
/// forwards the raw v8.17 stream. Expensive/syntax-aware H.264 validation runs
/// here on the iPhone before VideoToolbox sees a NAL. MainVideo is started only
/// while live U2W Map Mode is active, so normal Navigation/Freeride adds zero
/// MainVideo HTTP load to the old Carlinkit hardware.
@MainActor
@Observable
final class U2WMainVideoClient {
    private(set) var latestFrame: UIImage?
    private(set) var status = "U2W main video idle — Map Mode off"
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

    var sanitizerSummary: String {
        "raw \(rawNALCount) • valid \(acceptedNALCount) • rejected \(rejectedNALCount) • " +
        "SPS \(acceptedSPSCount) PPS \(acceptedPPSCount) IDR \(acceptedIDRCount) slices \(acceptedSliceCount)"
    }

    private let logger: LogManager
    private var worker: U2WMainVideoStreamWorker?
    private var workerGeneration = 0
    private var running = false
    private var freshnessTask: Task<Void, Never>?
    private var connectedAt: Date?
    private var lastDecodedFrameAt: Date?
    private var lastReceivedBytesAt: Date?
    private var lastLocalDecoderResyncAt: Date?
    private var lastSourceReconnectAt: Date?

    // Do not churn HTTP while the raw adapter stream remains active. A long span
    // of contaminated/non-video bytes is handled locally by the sanitizer. Only
    // true source silence permits a rate-limited transport reconnect.
    private let decoderStaleFrameInterval: TimeInterval = 20.0
    private let localDecoderResyncCooldown: TimeInterval = 30.0
    private let sourceStaleInterval: TimeInterval = 60.0
    private let sourceReconnectCooldown: TimeInterval = 60.0

    init(logger: LogManager) {
        self.logger = logger
    }

    func start(reason: String) {
        guard !running else { return }
        running = true
        status = "Connecting to U2W v8.17 raw MainVideo…"
        latestFrame = nil
        frameCount = 0
        sourceSize = "—"
        receivedBytes = 0
        connectedAt = nil
        lastDecodedFrameAt = nil
        lastReceivedBytesAt = nil
        lastLocalDecoderResyncAt = nil
        lastSourceReconnectAt = nil
        rawNALCount = 0
        acceptedNALCount = 0
        rejectedNALCount = 0
        acceptedSPSCount = 0
        acceptedPPSCount = 0
        acceptedIDRCount = 0
        acceptedSliceCount = 0
        logger.log("U2W VIDEO", "Start reason=\(reason) architecture=v8.17-raw+iPhone-filter mapModeOnly=1")
        startWorker(reason: reason)
        startFreshnessWatchdog()
    }

    private func startWorker(reason: String) {
        worker?.stop()
        workerGeneration &+= 1
        let generation = workerGeneration
        connectedAt = nil
        lastDecodedFrameAt = nil
        lastReceivedBytesAt = nil

        let worker = U2WMainVideoStreamWorker(
            endpoint: URL(string: "http://192.168.50.2/cgi-bin/u2wvideo-main-stream.cgi")!
        )
        worker.onStatus = { [weak self] message, isConnected in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.workerGeneration == generation else { return }
                let wasConnected = self.connected
                self.status = message
                self.connected = isConnected
                if isConnected, !wasConnected || self.connectedAt == nil {
                    self.connectedAt = Date()
                } else if !isConnected {
                    self.connectedAt = nil
                }
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
        worker.onFrame = { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.workerGeneration == generation else { return }
                // Single-frame mailbox: every newly published frame replaces the
                // prior one. The 5-fps HUD renderer always consumes the newest image.
                self.latestFrame = image
                self.lastDecodedFrameAt = Date()
                self.frameCount += 1
                self.sourceSize = "\(Int(image.size.width))×\(Int(image.size.height))"
                self.status = "Live U2W map video • iPhone H.264 filter"
                if self.frameCount == 1 || self.frameCount % 75 == 0 {
                    self.logger.log(
                        "U2W VIDEO",
                        "Live frame #\(self.frameCount) source=\(self.sourceSize) filter={\(self.sanitizerSummary)}"
                    )
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
        logger.log("U2W VIDEO", "Worker opened reason=\(reason)")
    }

    private func startFreshnessWatchdog() {
        freshnessTask?.cancel()
        freshnessTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.running {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, self.running, self.connected,
                      let connectedAt = self.connectedAt else { continue }

                let now = Date()
                let referenceFrameTime = self.lastDecodedFrameAt ?? connectedAt
                let frameAge = now.timeIntervalSince(referenceFrameTime)
                let byteAge = self.lastReceivedBytesAt.map { now.timeIntervalSince($0) } ?? .infinity
                let bytesAreFresh = byteAge < 2.0

                if bytesAreFresh, frameAge >= self.decoderStaleFrameInterval {
                    let mayResync = self.lastLocalDecoderResyncAt.map {
                        now.timeIntervalSince($0) >= self.localDecoderResyncCooldown
                    } ?? true
                    guard mayResync else { continue }
                    self.lastLocalDecoderResyncAt = now
                    self.status = "Raw MainVideo active — waiting for valid 800×480 H.264"
                    self.logger.log(
                        "U2W VIDEO WATCH",
                        "raw bytes fresh byteAge=\(String(format: "%.1f", byteAge))s frameAge=\(String(format: "%.1f", frameAge))s; local decoder resync only, HTTP stream remains open; filter={\(self.sanitizerSummary)}"
                    )
                    self.worker?.requestDecoderResync(reason: "fresh raw bytes but no validated live image")
                    continue
                }

                guard !bytesAreFresh,
                      byteAge >= self.sourceStaleInterval else { continue }
                let mayReconnect = self.lastSourceReconnectAt.map {
                    now.timeIntervalSince($0) >= self.sourceReconnectCooldown
                } ?? true
                guard mayReconnect else { continue }

                self.lastSourceReconnectAt = now
                self.status = "U2W MainVideo source silent — reconnecting once…"
                self.logger.log(
                    "U2W VIDEO WATCH",
                    "source silent for \(byteAge.isFinite ? String(format: "%.1f", byteAge) : "unknown")s frameAge=\(String(format: "%.1f", frameAge))s; one rate-limited v8.17 HTTP reconnect"
                )
                self.connected = false
                self.connectedAt = nil
                if let worker = self.worker {
                    worker.reconnectAtLiveEdge(reason: "source silent >=60s")
                } else {
                    self.startWorker(reason: "source silent >=60s")
                }
            }
        }
    }

    func stop(reason: String) {
        guard running || worker != nil else {
            status = "U2W main video idle — Map Mode off"
            return
        }
        running = false
        freshnessTask?.cancel()
        freshnessTask = nil
        worker?.stop()
        worker = nil
        workerGeneration &+= 1
        connected = false
        latestFrame = nil
        connectedAt = nil
        lastDecodedFrameAt = nil
        lastReceivedBytesAt = nil
        lastLocalDecoderResyncAt = nil
        lastSourceReconnectAt = nil
        status = "U2W main video idle — Map Mode off"
        logger.log("U2W VIDEO", "Stop reason=\(reason); no MainVideo HTTP traffic remains")
    }

    func reconnect(reason: String = "manual") {
        guard running else {
            status = "Enable Map Mode before reconnecting U2W video"
            logger.log("U2W VIDEO", "Ignored reconnect while Map Mode video is idle reason=\(reason)")
            return
        }
        connected = false
        connectedAt = nil
        lastDecodedFrameAt = nil
        lastReceivedBytesAt = nil
        lastSourceReconnectAt = Date()
        status = "Reconnecting U2W v8.17 raw MainVideo…"
        logger.log("U2W VIDEO", "Manual reconnect reason=\(reason)")
        if let worker {
            worker.reconnectAtLiveEdge(reason: "manual / \(reason)")
        } else {
            startWorker(reason: "manual reconnect / \(reason)")
        }
    }
}

/// URLSession streaming worker. Raw v8.17 bytes are split and syntax-validated
/// on the iPhone before VideoToolbox submission. The delegate queue is serial so
/// H.264 ordering is deterministic and adapter-side computation stays minimal.
private final class U2WMainVideoStreamWorker: NSObject, URLSessionDataDelegate {
    let endpoint: URL
    var onStatus: ((String, Bool) -> Void)?
    var onBytes: ((Int) -> Void)?
    var onFrame: ((UIImage) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onSanitizerStats: ((H264MainVideoSanitizerStats) -> Void)?

    private let parser = AnnexBH264Parser()
    private let sanitizer = H264MainVideoSanitizer()
    private let decoder = H264VideoToolboxDecoder()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var running = false
    private var reconnectWorkItem: DispatchWorkItem?
    private var lastStatsEmitUptime: TimeInterval = 0
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        queue.name = "HUD.U2WMainVideo.Serial"
        return queue
    }()

    init(endpoint: URL) {
        self.endpoint = endpoint
        super.init()
        decoder.onFrame = { [weak self] image in
            self?.onFrame?(image)
        }
        decoder.onDiagnostic = { [weak self] message in
            self?.onDiagnostic?(message)
        }
    }

    func start() {
        guard !running else { return }
        running = true
        let configuration = URLSessionConfiguration.ephemeral
        // v8.17 is a lightweight byte streamer. Keep one long-lived request and
        // tolerate long dirty spans instead of reopening a CGI every ~15 seconds.
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 6
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        parser.reset()
        sanitizer.reset()
        decoder.reset()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
        openStream()
    }

    func stop() {
        running = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        parser.reset()
        sanitizer.reset()
        decoder.reset()
    }

    private func openStream() {
        guard running, let session else { return }
        parser.reset()
        sanitizer.prepareForTransportReconnect()
        decoder.prepareForStreamRestart()
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        task = session.dataTask(with: request)
        task?.resume()
        onStatus?("Opening U2W v8.17 raw H.264 stream…", false)
    }

    func requestDecoderResync(reason: String) {
        guard running else { return }
        delegateQueue.addOperation { [weak self] in
            guard let self, self.running else { return }
            self.decoder.prepareForStreamRestart()
            self.onDiagnostic?("Local decoder resync reason=\(reason); raw HTTP stream left open")
        }
    }

    func reconnectAtLiveEdge(reason: String) {
        guard running else { return }
        delegateQueue.addOperation { [weak self] in
            guard let self, self.running else { return }
            self.reconnectWorkItem?.cancel()
            self.reconnectWorkItem = nil
            let previous = self.task
            self.task = nil
            previous?.cancel()
            self.onDiagnostic?("Transport reconnect requested reason=\(reason); retaining validated SPS/PPS relationship")
            self.openStream()
        }
    }

    private func isCurrent(_ dataTask: URLSessionDataTask) -> Bool {
        task?.taskIdentifier == dataTask.taskIdentifier
    }

    private func scheduleReconnect(_ detail: String) {
        guard running else { return }
        onStatus?("U2W video unavailable — retrying in 5s: \(detail)", false)
        reconnectWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.delegateQueue.addOperation { [weak self] in
                guard let self, self.running else { return }
                self.openStream()
            }
        }
        reconnectWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5.0, execute: item)
    }

    private func emitSanitizerStats(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || lastStatsEmitUptime == 0 || now - lastStatsEmitUptime >= 1.0 else { return }
        lastStatsEmitUptime = now
        onSanitizerStats?(sanitizer.stats)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard isCurrent(dataTask) else {
            completionHandler(.cancel)
            return
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            completionHandler(.cancel)
            scheduleReconnect("HTTP \(http.statusCode)")
            return
        }
        onStatus?("U2W v8.17 raw MainVideo connected • filtering on iPhone", true)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard isCurrent(dataTask) else { return }
        onBytes?(data.count)
        for nal in parser.append(data) {
            if let accepted = sanitizer.process(nal) {
                decoder.consume(accepted.data)
                switch accepted.kind {
                case .sps, .pps:
                    onDiagnostic?("iPhone filter accepted \(accepted.kind.rawValue) • \(sanitizer.stats.summary)")
                case .idr:
                    let count = sanitizer.stats.acceptedIDR
                    if count <= 3 || count % 10 == 0 {
                        onDiagnostic?("iPhone filter accepted IDR #\(count) • \(sanitizer.stats.summary)")
                    }
                case .slice:
                    break
                }
            }
        }
        emitSanitizerStats()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard running, self.task?.taskIdentifier == task.taskIdentifier else { return }
        self.task = nil
        decoder.discardPendingAccessUnit()
        emitSanitizerStats(force: true)
        scheduleReconnect(error?.localizedDescription ?? "stream ended")
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
/// - requires a fresh IDR after every decoder reset, and
/// - publishes at most 15 images/s while always replacing the latest mailbox.
private final class H264VideoToolboxDecoder {
    var onFrame: ((UIImage) -> Void)?
    var onDiagnostic: ((String) -> Void)?

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
    private var decodeErrors = 0

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
        decodeErrors = 0
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
        decodeErrors = 0
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
                    guard status == noErr,
                          let outputRefCon,
                          let imageBuffer else { return }
                    let decoder = Unmanaged<H264VideoToolboxDecoder>
                        .fromOpaque(outputRefCon)
                        .takeUnretainedValue()
                    decoder.publish(imageBuffer)
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
        guard let decompressionSession, let formatDescription else { return }
        let hasIDR = nals.contains { ($0.first ?? 0) & 0x1F == 5 }
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

        if decodeStatus != noErr {
            decodeErrors += 1
            needsIDR = true
            onDiagnostic?(
                "Decode error status=\(decodeStatus) au=\(submittedAccessUnits) errors=\(decodeErrors); waiting for fresh IDR"
            )
            if decodeErrors >= 3, let activeSPS, let activePPS {
                // A VideoToolbox session can become poisoned after repeated bad
                // access units even though the accepted parameter sets remain good.
                // Recreate only the decoder session; do not throw away the known-good
                // SPS/PPS or reconnect the HTTP stream just for this condition.
                pendingSPS = activeSPS
                pendingPPS = activePPS
                decodeErrors = 0
                onDiagnostic?("Rebuilding decoder from last-known-good SPS/PPS after repeated decode errors")
                promoteValidParameterSetPairIfPossible()
            }
        } else {
            decodeErrors = 0
            if submittedAccessUnits == 1 || submittedAccessUnits % 300 == 0 {
                onDiagnostic?("Decoded access unit #\(submittedAccessUnits) nals=\(nals.count)")
            }
        }
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
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }
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

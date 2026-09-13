import Foundation
import Observation
import UIKit
import VideoToolbox
import CoreMedia
import CoreImage

/// v90.35.3.13 live MainVideo client for U2W v8.17.
///
/// The adapter exposes the existing CarPlay H.264 stream as Annex-B at
/// /cgi-bin/u2wvideo-main-stream.cgi. This path is deliberately content-blind:
/// whatever CarPlay is currently drawing is decoded, and Map Mode crops the
/// configured rectangle from the newest available frame. No app/map/dashboard
/// validation and no OCR are involved.
@MainActor
@Observable
final class U2WMainVideoClient {
    private(set) var latestFrame: UIImage?
    private(set) var status = "U2W main video idle"
    private(set) var frameCount = 0
    private(set) var connected = false
    private(set) var sourceSize = "—"
    private(set) var receivedBytes: Int64 = 0

    private let logger: LogManager
    private var worker: U2WMainVideoStreamWorker?
    private var workerGeneration = 0
    private var running = false
    private var freshnessTask: Task<Void, Never>?
    private var connectedAt: Date?
    private var lastDecodedFrameAt: Date?
    private var lastReceivedBytesAt: Date?
    private var lastFreshnessReconnectAt: Date?

    // A decoder that is receiving bytes but not producing images is unhealthy
    // quickly enough that a 10-second frozen HUD is unnecessary. Source silence
    // gets a longer allowance because a truly static CarPlay frame can compress
    // down to very little traffic.
    private let decoderStaleFrameInterval: TimeInterval = 3.0
    private let sourceStaleInterval: TimeInterval = 12.0
    private let freshnessReconnectCooldown: TimeInterval = 4.0

    init(logger: LogManager) {
        self.logger = logger
    }

    func start(reason: String) {
        guard !running else { return }
        running = true
        status = "Connecting to U2W main video…"
        connectedAt = nil
        lastDecodedFrameAt = nil
        lastReceivedBytesAt = nil
        logger.log("U2W VIDEO", "Start reason=\(reason)")
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
        worker.onFrame = { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.workerGeneration == generation else { return }
                // Single-frame mailbox: every newly published frame simply replaces
                // the prior one. Nothing downstream can build a video backlog.
                self.latestFrame = image
                self.lastDecodedFrameAt = Date()
                self.frameCount += 1
                self.sourceSize = "\(Int(image.size.width))×\(Int(image.size.height))"
                if self.frameCount == 1 || self.frameCount % 75 == 0 {
                    self.logger.log(
                        "U2W VIDEO",
                        "Live frame #\(self.frameCount) source=\(self.sourceSize)"
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
                let bytesAreFresh = byteAge < 1.5

                let decoderStalled = bytesAreFresh && frameAge >= self.decoderStaleFrameInterval
                let sourceStalled = !bytesAreFresh && frameAge >= self.sourceStaleInterval
                guard decoderStalled || sourceStalled else { continue }

                if let lastFreshnessReconnectAt = self.lastFreshnessReconnectAt,
                   now.timeIntervalSince(lastFreshnessReconnectAt) < self.freshnessReconnectCooldown {
                    continue
                }

                self.lastFreshnessReconnectAt = now
                let detail: String
                if decoderStalled {
                    detail = "H.264 bytes fresh (byteAge=\(String(format: "%.1f", byteAge))s), no live image for \(String(format: "%.1f", frameAge))s"
                } else {
                    detail = "source silent for \(byteAge.isFinite ? String(format: "%.1f", byteAge) : "unknown")s, no live image for \(String(format: "%.1f", frameAge))s"
                }
                self.status = "U2W main video stale — reconnecting…"
                self.logger.log(
                    "U2W VIDEO WATCH",
                    "\(detail); hard-resetting decoder and reconnecting at v8.17 latest GOP"
                )
                self.connected = false
                self.connectedAt = nil
                self.lastDecodedFrameAt = nil
                self.lastReceivedBytesAt = nil
                self.startWorker(reason: decoderStalled ? "decoder freshness watchdog" : "source freshness watchdog")
            }
        }
    }

    func stop(reason: String) {
        guard running || worker != nil else { return }
        running = false
        freshnessTask?.cancel()
        freshnessTask = nil
        worker?.stop()
        worker = nil
        workerGeneration &+= 1
        connected = false
        connectedAt = nil
        lastDecodedFrameAt = nil
        lastReceivedBytesAt = nil
        status = "U2W main video stopped"
        logger.log("U2W VIDEO", "Stop reason=\(reason)")
    }

    func reconnect(reason: String = "manual") {
        guard running else {
            start(reason: "reconnect / \(reason)")
            return
        }
        connected = false
        connectedAt = nil
        lastDecodedFrameAt = nil
        lastReceivedBytesAt = nil
        lastFreshnessReconnectAt = Date()
        status = "Reconnecting U2W main video…"
        logger.log("U2W VIDEO", "Reconnect reason=\(reason)")
        startWorker(reason: "reconnect / \(reason)")
    }
}

/// URLSession streaming worker. H.264 parsing and VideoToolbox submission are
/// intentionally kept off the main actor. The delegate queue is serial so access
/// units are fed to the decoder in wire order.
private final class U2WMainVideoStreamWorker: NSObject, URLSessionDataDelegate {
    let endpoint: URL
    var onStatus: ((String, Bool) -> Void)?
    var onBytes: ((Int) -> Void)?
    var onFrame: ((UIImage) -> Void)?
    var onDiagnostic: ((String) -> Void)?

    private let parser = AnnexBH264Parser()
    private let decoder = H264VideoToolboxDecoder()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var running = false
    private var reconnectWorkItem: DispatchWorkItem?

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
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60 * 60 * 6
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
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
        decoder.reset()
    }

    private func openStream() {
        guard running, let session else { return }
        parser.reset()
        decoder.reset()
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        task = session.dataTask(with: request)
        task?.resume()
        onStatus?("Opening U2W H.264 stream…", false)
    }

    private func scheduleReconnect(_ detail: String) {
        guard running else { return }
        onStatus?("U2W video unavailable — retrying: \(detail)", false)
        reconnectWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.openStream()
        }
        reconnectWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            completionHandler(.cancel)
            scheduleReconnect("HTTP \(http.statusCode)")
            return
        }
        onStatus?("U2W live main video connected", true)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        onBytes?(data.count)
        for nal in parser.append(data) {
            decoder.consume(nal)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard running else { return }
        decoder.discardPendingAccessUnit()
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
            output.append(buffer.subdata(in: payloadStart..<next.offset))
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

    private var sps: Data?
    private var pps: Data?
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
        sps = nil
        pps = nil
        needsIDR = true
        submittedAccessUnits = 0
        decodeErrors = 0
        publishLock.lock()
        lastPublishedUptime = 0
        publishLock.unlock()
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
            if sps != nal {
                sps = nal
                rebuildSessionIfPossible()
            }
        case 8: // PPS
            flushAccessUnit()
            if pps != nal {
                pps = nal
                rebuildSessionIfPossible()
            }
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

    private func rebuildSessionIfPossible() {
        guard let sps, let pps else { return }

        var description: CMVideoFormatDescription?
        let status: OSStatus = sps.withUnsafeBytes { spsRaw in
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
                            formatDescriptionOut: &description
                        )
                    }
                }
            }
        }
        guard status == noErr, let videoDescription = description else {
            onDiagnostic?("Could not build H.264 format description status=\(status)")
            return
        }

        if let decompressionSession {
            VTDecompressionSessionInvalidate(decompressionSession)
        }
        decompressionSession = nil
        formatDescription = videoDescription
        needsIDR = true

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
        var session: VTDecompressionSession?
        let createStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: videoDescription,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
        if createStatus == noErr, let session {
            decompressionSession = session
            onDiagnostic?("Decoder session ready; waiting for current IDR")
        } else {
            onDiagnostic?("Decoder session creation failed status=\(createStatus)")
        }
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
        } else if submittedAccessUnits == 1 || submittedAccessUnits % 300 == 0 {
            onDiagnostic?("Decoded access unit #\(submittedAccessUnits) nals=\(nals.count)")
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

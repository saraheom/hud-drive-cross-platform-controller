import Foundation
import Observation
import UIKit
import VideoToolbox
import CoreMedia
import CoreImage

/// v90.35.1 live main-CarPlay-video client for U2W v8.11.
///
/// The adapter exposes the already-existing CarPlay H.264 stream as Annex-B at
/// /cgi-bin/u2wvideo-main-stream.cgi. This class never requests ScreenCaptureKit
/// and never performs OCR. It decodes frames locally with VideoToolbox and keeps
/// only the latest UIImage for the Map Mode center crop.
@MainActor
@Observable
final class U2WMainVideoClient {
    private(set) var latestFrame: UIImage?
    private(set) var status = "U2W main video idle"
    private(set) var frameCount = 0
    private(set) var connected = false
    private(set) var sourceSize = "—"

    private let logger: LogManager
    private var worker: U2WMainVideoStreamWorker?
    private var running = false

    init(logger: LogManager) {
        self.logger = logger
    }

    func start(reason: String) {
        guard !running else { return }
        running = true
        status = "Connecting to U2W main video…"
        logger.log("U2W VIDEO", "Start reason=\(reason)")

        let worker = U2WMainVideoStreamWorker(
            endpoint: URL(string: "http://192.168.50.2/cgi-bin/u2wvideo-main-stream.cgi")!
        )
        worker.onStatus = { [weak self] message, isConnected in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.status = message
                self.connected = isConnected
                self.logger.log("U2W VIDEO", message)
            }
        }
        worker.onFrame = { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, self.running else { return }
                self.latestFrame = image
                self.frameCount += 1
                self.sourceSize = "\(Int(image.size.width))×\(Int(image.size.height))"
                if self.frameCount == 1 || self.frameCount % 120 == 0 {
                    self.logger.log(
                        "U2W VIDEO",
                        "Decoded frame #\(self.frameCount) source=\(self.sourceSize)"
                    )
                }
            }
        }
        self.worker = worker
        worker.start()
    }

    func stop(reason: String) {
        guard running || worker != nil else { return }
        running = false
        worker?.stop()
        worker = nil
        connected = false
        status = "U2W main video stopped"
        logger.log("U2W VIDEO", "Stop reason=\(reason)")
    }

    func reconnect(reason: String = "manual") {
        stop(reason: "reconnect / \(reason)")
        start(reason: "reconnect / \(reason)")
    }
}

/// URLSession streaming worker. Kept outside the @MainActor observable object so
/// H.264 parsing and VideoToolbox submission do not run on the UI actor.
private final class U2WMainVideoStreamWorker: NSObject, URLSessionDataDelegate {
    let endpoint: URL
    var onStatus: ((String, Bool) -> Void)?
    var onFrame: ((UIImage) -> Void)?

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
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0, execute: item)
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
                // Corrupt/non-Annex-B input should not grow without bound.
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

private final class H264VideoToolboxDecoder {
    var onFrame: ((UIImage) -> Void)?

    private var sps: Data?
    private var pps: Data?
    private var formatDescription: CMVideoFormatDescription?
    private var decompressionSession: VTDecompressionSession?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func reset() {
        if let decompressionSession {
            VTDecompressionSessionInvalidate(decompressionSession)
        }
        decompressionSession = nil
        formatDescription = nil
        sps = nil
        pps = nil
    }

    func consume(_ nal: Data) {
        guard let first = nal.first else { return }
        let type = first & 0x1F
        switch type {
        case 7:
            if sps != nal {
                sps = nal
                rebuildSessionIfPossible()
            }
        case 8:
            if pps != nal {
                pps = nal
                rebuildSessionIfPossible()
            }
        case 1, 5:
            decodeSlice(nal)
        default:
            break
        }
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
        guard status == noErr, let videoDescription = description else { return }

        if let decompressionSession {
            VTDecompressionSessionInvalidate(decompressionSession)
        }
        decompressionSession = nil
        formatDescription = videoDescription

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
        if createStatus == noErr {
            decompressionSession = session
        }
    }

    private func decodeSlice(_ nal: Data) {
        guard let decompressionSession, let formatDescription else { return }

        var avcc = Data(count: 4)
        let length = UInt32(nal.count).bigEndian
        withUnsafeBytes(of: length) { avcc.replaceSubrange(0..<4, with: $0) }
        avcc.append(nal)

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
        guard blockStatus == noErr, let blockBuffer else { return }

        let copyStatus: OSStatus = avcc.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: avcc.count
            )
        }
        guard copyStatus == noErr else { return }

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
        guard sampleStatus == noErr, let sampleBuffer else { return }

        var infoFlags = VTDecodeInfoFlags()
        VTDecompressionSessionDecodeFrame(
            decompressionSession,
            sampleBuffer: sampleBuffer,
            flags: VTDecodeFrameFlags(rawValue: 1 << 0),
            frameRefcon: nil,
            infoFlagsOut: &infoFlags
        )
    }

    private func publish(_ pixelBuffer: CVImageBuffer) {
        let image = CIImage(cvImageBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }
        onFrame?(UIImage(cgImage: cgImage))
    }
}

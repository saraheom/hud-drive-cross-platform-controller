import Foundation
import AVFoundation
import UIKit
import CryptoKit

struct PreparedBootAnimation: Sendable {
    let url: URL
    let sourceName: String
    let frameCount: Int
    let durationSeconds: Double
    let byteCount: Int64
    let sha256: String
}

enum BootAnimationBuildError: LocalizedError {
    case unsupportedFile
    case videoTooLong(Double)
    case invalidDuration
    case frameGenerationFailed(Int)
    case pngEncodingFailed(Int)
    case invalidZip(String)
    case archiveTooLarge(Int64)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: return "Choose an MP4/MOV video or an Android bootanimation.zip."
        case .videoTooLong(let seconds): return String(format: "Video is %.1f seconds. This build limits boot animations to 12 seconds for the first safe test.", seconds)
        case .invalidDuration: return "The selected video has no usable duration."
        case .frameGenerationFailed(let index): return "Could not generate video frame \(index)."
        case .pngEncodingFailed(let index): return "Could not encode video frame \(index) as PNG."
        case .invalidZip(let detail): return "Invalid bootanimation.zip: \(detail)"
        case .archiveTooLarge(let bytes): return String(format: "Boot animation archive is %.1f MB. This first safe build limits the override to 100 MB.", Double(bytes) / 1_048_576.0)
        }
    }
}

enum BootAnimationBuilder {
    static let width = 480
    static let height = 240
    static let fps = 24
    static let maximumDuration = 12.0
    static let maximumArchiveBytes: Int64 = 100 * 1024 * 1024

    static func prepare(from sourceURL: URL,
                        progress: @escaping @Sendable (Double, String) -> Void) async throws -> PreparedBootAnimation {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.lowercased()
        if ext == "zip" {
            let copied = try copyToTemporary(sourceURL, name: "bootanimation-imported.zip")
            let validation = try validateZip(copied)
            let hash = try sha256File(copied)
            let size = try fileSize(copied)
            progress(1.0, "Prepared imported bootanimation.zip")
            return PreparedBootAnimation(
                url: copied,
                sourceName: sourceURL.lastPathComponent,
                frameCount: validation.frameCount,
                durationSeconds: validation.durationSeconds,
                byteCount: size,
                sha256: hash
            )
        }
        guard ["mp4", "mov", "m4v"].contains(ext) else { throw BootAnimationBuildError.unsupportedFile }

        let localVideo = try copyToTemporary(sourceURL, name: "bootanimation-source.\(ext)")
        return try await Task.detached(priority: .userInitiated) {
            try buildVideo(localVideo, originalName: sourceURL.lastPathComponent, progress: progress)
        }.value
    }

    private static func buildVideo(_ videoURL: URL,
                                   originalName: String,
                                   progress: @escaping @Sendable (Double, String) -> Void) throws -> PreparedBootAnimation {
        let asset = AVURLAsset(url: videoURL)
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0 else { throw BootAnimationBuildError.invalidDuration }
        guard duration <= maximumDuration else { throw BootAnimationBuildError.videoTooLong(duration) }

        let frameCount = max(1, Int((duration * Double(fps)).rounded(.down)))
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("HUDWAY_bootanimation_\(UUID().uuidString).zip")
        let writer = try StoredZipWriter(url: output)
        try writer.add(name: "desc.txt", data: Data("480 240 24\np 1 0 part0\np 0 0 part1\n\n".utf8))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 48)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 48)

        var lastPNG: Data?
        for index in 0..<frameCount {
            autoreleasepool {
                progress(Double(index) / Double(max(1, frameCount)), "Converting frame \(index + 1) / \(frameCount)")
            }
            let time = CMTime(seconds: Double(index) / Double(fps), preferredTimescale: 600)
            var actual = CMTime.zero
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: &actual) else {
                throw BootAnimationBuildError.frameGenerationFailed(index)
            }
            let image = renderAspectFit(cgImage)
            guard let png = image.pngData() else { throw BootAnimationBuildError.pngEncodingFailed(index) }
            lastPNG = png
            try writer.add(name: String(format: "part0/frame_%03d.png", index), data: png)
        }

        guard let lastPNG else { throw BootAnimationBuildError.frameGenerationFailed(0) }
        try writer.add(name: "part1/frame_000.png", data: lastPNG)
        try writer.finish()
        let archiveBytes = try fileSize(output)
        guard archiveBytes <= maximumArchiveBytes else {
            try? FileManager.default.removeItem(at: output)
            throw BootAnimationBuildError.archiveTooLarge(archiveBytes)
        }
        progress(1.0, "Boot animation package ready")

        return PreparedBootAnimation(
            url: output,
            sourceName: originalName,
            frameCount: frameCount,
            durationSeconds: duration,
            byteCount: archiveBytes,
            sha256: try sha256File(output)
        )
    }

    private static func renderAspectFit(_ image: CGImage) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        // The HUD expects actual 480×240 PNG pixels. The default renderer uses
        // the iPhone screen scale (2×/3×), which would silently produce oversized
        // frames even though the logical point size is 480×240.
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let source = CGSize(width: image.width, height: image.height)
            let scale = min(size.width / source.width, size.height / source.height)
            let draw = CGSize(width: source.width * scale, height: source.height * scale)
            let rect = CGRect(
                x: (size.width - draw.width) / 2,
                y: (size.height - draw.height) / 2,
                width: draw.width,
                height: draw.height
            )
            UIImage(cgImage: image).draw(in: rect)
        }
    }

    private static func copyToTemporary(_ source: URL, name: String) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(name)")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private static func validateZip(_ url: URL) throws -> (frameCount: Int, durationSeconds: Double) {
        let size = try fileSize(url)
        guard size <= maximumArchiveBytes else { throw BootAnimationBuildError.archiveTooLarge(size) }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let entries = try ZipCentralDirectory.entries(in: data)
        guard let descEntry = entries.first(where: { $0.name == "desc.txt" }) else {
            throw BootAnimationBuildError.invalidZip("missing root desc.txt")
        }
        guard descEntry.compressionMethod == 0 else {
            throw BootAnimationBuildError.invalidZip("desc.txt must use ZIP STORE / no compression")
        }
        let descData = try ZipCentralDirectory.extractStored(descEntry, from: data)
        let desc = String(data: descData, encoding: .utf8) ?? ""
        guard desc.contains("480 240 24"),
              desc.contains("p 1 0 part0"),
              desc.contains("p 0 0 part1") else {
            throw BootAnimationBuildError.invalidZip("desc.txt must match HUDWAY Drive 480×240 @ 24 fps with part0 once + part1 loop")
        }

        let frames = entries.filter { $0.name.hasPrefix("part0/") && $0.name.lowercased().hasSuffix(".png") }
        guard !frames.isEmpty else { throw BootAnimationBuildError.invalidZip("no PNG frames in part0") }
        guard frames.allSatisfy({ $0.compressionMethod == 0 }) else {
            throw BootAnimationBuildError.invalidZip("PNG frames must use ZIP STORE / no compression")
        }
        for frame in frames {
            let png = try ZipCentralDirectory.extractStored(frame, from: data)
            guard let dimensions = pngDimensions(png),
                  dimensions.0 == width, dimensions.1 == height else {
                throw BootAnimationBuildError.invalidZip("\(frame.name) must be exactly 480×240 pixels")
            }
        }
        guard let loop = entries.first(where: { $0.name == "part1/frame_000.png" }), loop.compressionMethod == 0 else {
            throw BootAnimationBuildError.invalidZip("missing stored part1/frame_000.png loop frame")
        }
        let loopPNG = try ZipCentralDirectory.extractStored(loop, from: data)
        guard let loopDimensions = pngDimensions(loopPNG),
              loopDimensions.0 == width, loopDimensions.1 == height else {
            throw BootAnimationBuildError.invalidZip("part1/frame_000.png must be exactly 480×240 pixels")
        }
        return (frames.count, Double(frames.count) / Double(fps))
    }


    private static func pngDimensions(_ data: Data) -> (Int, Int)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 24,
              Array(bytes[0..<8]) == [137, 80, 78, 71, 13, 10, 26, 10],
              String(decoding: bytes[12..<16], as: UTF8.self) == "IHDR" else { return nil }
        func be32(_ offset: Int) -> Int {
            (Int(bytes[offset]) << 24) |
            (Int(bytes[offset + 1]) << 16) |
            (Int(bytes[offset + 2]) << 8) |
            Int(bytes[offset + 3])
        }
        return (be32(16), be32(20))
    }

    static func sha256File(_ url: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw BootAnimationBuildError.unsupportedFile }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fileSize(_ url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }
}

private final class StoredZipWriter {
    private struct Entry {
        let name: Data
        let crc32: UInt32
        let size: UInt32
        let localOffset: UInt32
    }

    private let handle: FileHandle
    private var entries: [Entry] = []
    private var offset: UInt32 = 0
    private var finished = false

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    deinit { try? handle.close() }

    func add(name: String, data: Data) throws {
        let nameData = Data(name.utf8)
        let crc = CRC32.checksum(data)
        let size = UInt32(data.count)
        let localOffset = offset

        var header = Data()
        header.appendLE(0x04034b50)
        header.appendLE16(20)
        header.appendLE16(0)
        header.appendLE16(0) // STORE; Android bootanimation prefers uncompressed entries.
        header.appendLE16(0)
        header.appendLE16(0)
        header.appendLE(crc)
        header.appendLE(size)
        header.appendLE(size)
        header.appendLE16(UInt16(nameData.count))
        header.appendLE16(0)
        header.append(nameData)

        try handle.write(contentsOf: header)
        try handle.write(contentsOf: data)
        offset &+= UInt32(header.count + data.count)
        entries.append(Entry(name: nameData, crc32: crc, size: size, localOffset: localOffset))
    }

    func finish() throws {
        guard !finished else { return }
        let centralOffset = offset
        var central = Data()
        for entry in entries {
            central.appendLE(0x02014b50)
            central.appendLE16(20)
            central.appendLE16(20)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE(entry.crc32)
            central.appendLE(entry.size)
            central.appendLE(entry.size)
            central.appendLE16(UInt16(entry.name.count))
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE(0)
            central.appendLE(entry.localOffset)
            central.append(entry.name)
        }
        try handle.write(contentsOf: central)
        offset &+= UInt32(central.count)

        var end = Data()
        end.appendLE(0x06054b50)
        end.appendLE16(0)
        end.appendLE16(0)
        end.appendLE16(UInt16(entries.count))
        end.appendLE16(UInt16(entries.count))
        end.appendLE(UInt32(central.count))
        end.appendLE(centralOffset)
        end.appendLE16(0)
        try handle.write(contentsOf: end)
        try handle.synchronize()
        try handle.close()
        finished = true
    }
}

private enum CRC32 {
    static let table: [UInt32] = (0..<256).map { raw in
        var c = UInt32(raw)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : (c >> 1) }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }
}

private enum ZipCentralDirectory {
    struct Entry {
        let name: String
        let compressionMethod: UInt16
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
    }

    static func entries(in data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw BootAnimationBuildError.invalidZip("file is too small") }
        let endSignature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        var eocd: Int?
        let lower = max(0, bytes.count - 65_557)
        if bytes.count >= 4 {
            for i in stride(from: bytes.count - 4, through: lower, by: -1) {
                if Array(bytes[i..<(i + 4)]) == endSignature { eocd = i; break }
            }
        }
        guard let eocd else { throw BootAnimationBuildError.invalidZip("central directory footer not found") }
        let entryCount = Int(readLE16(bytes, eocd + 10))
        var cursor = Int(readLE32(bytes, eocd + 16))
        var result: [Entry] = []
        for _ in 0..<entryCount {
            guard cursor + 46 <= bytes.count,
                  readLE32(bytes, cursor) == 0x02014b50 else {
                throw BootAnimationBuildError.invalidZip("central directory entry is malformed")
            }
            let method = readLE16(bytes, cursor + 10)
            let compressed = readLE32(bytes, cursor + 20)
            let uncompressed = readLE32(bytes, cursor + 24)
            let nameLength = Int(readLE16(bytes, cursor + 28))
            let extraLength = Int(readLE16(bytes, cursor + 30))
            let commentLength = Int(readLE16(bytes, cursor + 32))
            let localOffset = readLE32(bytes, cursor + 42)
            let start = cursor + 46
            guard start + nameLength <= bytes.count else { throw BootAnimationBuildError.invalidZip("filename is truncated") }
            let name = String(decoding: bytes[start..<(start + nameLength)], as: UTF8.self)
            result.append(Entry(
                name: name,
                compressionMethod: method,
                compressedSize: compressed,
                uncompressedSize: uncompressed,
                localHeaderOffset: localOffset
            ))
            cursor = start + nameLength + extraLength + commentLength
        }
        return result
    }

    static func extractStored(_ entry: Entry, from data: Data) throws -> Data {
        guard entry.compressionMethod == 0 else { throw BootAnimationBuildError.invalidZip("entry \(entry.name) is compressed") }
        let bytes = [UInt8](data)
        let offset = Int(entry.localHeaderOffset)
        guard offset + 30 <= bytes.count, readLE32(bytes, offset) == 0x04034b50 else {
            throw BootAnimationBuildError.invalidZip("local header for \(entry.name) is malformed")
        }
        let nameLength = Int(readLE16(bytes, offset + 26))
        let extraLength = Int(readLE16(bytes, offset + 28))
        let start = offset + 30 + nameLength + extraLength
        let length = Int(entry.compressedSize)
        guard start + length <= bytes.count else { throw BootAnimationBuildError.invalidZip("entry \(entry.name) is truncated") }
        return Data(bytes[start..<(start + length)])
    }

    private static func readLE16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readLE32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) |
            (UInt32(bytes[offset + 1]) << 8) |
            (UInt32(bytes[offset + 2]) << 16) |
            (UInt32(bytes[offset + 3]) << 24)
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }

    mutating func appendLE16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }
}

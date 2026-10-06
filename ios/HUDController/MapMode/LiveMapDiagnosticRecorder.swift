import Foundation
import UIKit

/// v90.35.3.24.26 one-drive MainVideo + ELM forensic evidence recorder.
///
/// This recorder is intentionally iPhone-side and passive. It never signals or
/// restarts AppleCarPlay, never changes AppleCarPlay/Route Guidance behavior, and never
/// enables Map Mode. The TCP worker feeds it the exact raw bytes already being
/// delivered to the production Annex-B parser. Storage is bounded so a normal
/// commute can preserve startup + failure/recovery evidence without recording an
/// unbounded drive-long video.
final class LiveMapDiagnosticRecorder: @unchecked Sendable {
    private struct ActiveWindow {
        let label: String
        let url: URL
        let handle: FileHandle
        var postBytesRemaining: Int
    }

    private let queue = DispatchQueue(label: "HUD.LiveMapDiagnosticRecorder")
    private let fileManager = FileManager.default
    private let sessionDirectory: URL
    private let timelineURL: URL
    private let startupURL: URL
    private let imagesDirectory: URL
    private let rollingDirectory: URL
    private var timelineHandle: FileHandle?
    private var startupHandle: FileHandle?
    private var rollingHandle: FileHandle?
    private var rollingURL: URL?
    private var rollingSegmentBytes = 0
    private var rollingSegmentSequence = 0
    private var rollingSegments: [URL] = []
    private var startupBytes = 0
    private var totalRawBytes: UInt64 = 0
    private var prebufferChunks: [Data] = []
    private var prebufferBytes = 0
    private var firstFailurePrebufferChunks: [Data] = []
    private var firstFailurePrebufferBytes = 0
    private var activeWindows: [UUID: ActiveWindow] = [:]
    private var evidenceWindowCount = 0
    private var droppedWindowCount = 0
    private var firstFailureWindow: ActiveWindow?
    private var firstFailureTriggered = false
    private var firstFailureCompleted = false
    private var firstFailureLabel = "none"
    private var nextCheckpoint: UInt64 = 4 * 1024 * 1024
    private var capturedLabels: Set<String> = []

    private let startupLimit = 8 * 1024 * 1024
    /// Historical normal evidence windows retain a 4 MiB pre-fault tail.
    private let prebufferLimit = 4 * 1024 * 1024
    /// A separate larger tail is reserved solely for the first actual failure.
    private let firstFailurePrebufferLimit = 8 * 1024 * 1024
    private let normalEvidencePrebufferLimit = 4 * 1024 * 1024
    private let postbufferLimit = 4 * 1024 * 1024
    private let firstFailurePostbufferLimit = 8 * 1024 * 1024
    private let maximumEvidenceWindows = 6
    private let rollingSegmentLimit = 4 * 1024 * 1024
    private let maximumRollingSegments = 4

    init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let base = documents.appendingPathComponent("Live Map Diagnostics", isDirectory: true)
        let stamp = Self.timestamp()
        sessionDirectory = base.appendingPathComponent("LiveMap_\(stamp)", isDirectory: true)
        timelineURL = sessionDirectory.appendingPathComponent("timeline.jsonl")
        startupURL = sessionDirectory.appendingPathComponent("raw_startup_first_8MiB.h264")
        imagesDirectory = sessionDirectory.appendingPathComponent("images", isDirectory: true)
        rollingDirectory = sessionDirectory.appendingPathComponent("rolling_raw", isDirectory: true)

        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: rollingDirectory, withIntermediateDirectories: true)
        fileManager.createFile(atPath: timelineURL.path, contents: nil)
        fileManager.createFile(atPath: startupURL.path, contents: nil)
        timelineHandle = try? FileHandle(forWritingTo: timelineURL)
        startupHandle = try? FileHandle(forWritingTo: startupURL)
        record("recorder", "session_start", fields: [
            "architecture": "v8.31-navigation-priority-raw",
            "startup_limit_bytes": startupLimit,
            "prebuffer_bytes": prebufferLimit,
            "postbuffer_bytes": postbufferLimit,
            "first_failure_prebuffer_bytes": firstFailurePrebufferLimit,
            "first_failure_postbuffer_bytes": firstFailurePostbufferLimit,
            "rolling_segment_bytes": rollingSegmentLimit,
            "rolling_segment_count": maximumRollingSegments,
            "max_windows": maximumEvidenceWindows
        ])
    }

    deinit {
        queue.sync {
            for (_, window) in activeWindows { try? window.handle.close() }
            try? firstFailureWindow?.handle.close()
            try? rollingHandle?.close()
            try? startupHandle?.close()
            try? timelineHandle?.close()
        }
    }

    func record(_ category: String, _ message: String, fields: [String: Any] = [:]) {
        queue.async { [weak self] in
            self?.writeTimeline(category: category, message: message, fields: fields)
        }
    }

    /// Receives the exact v8.31 raw TCP bytes before Annex-B parsing.
    func ingestRawH264(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.totalRawBytes &+= UInt64(data.count)
            self.writeRollingRaw(data)

            if self.startupBytes < self.startupLimit {
                let remaining = self.startupLimit - self.startupBytes
                let slice = data.prefix(remaining)
                try? self.startupHandle?.write(contentsOf: slice)
                self.startupBytes += slice.count
            }

            self.prebufferChunks.append(data)
            self.prebufferBytes += data.count
            while self.prebufferBytes > self.prebufferLimit, !self.prebufferChunks.isEmpty {
                let excess = self.prebufferBytes - self.prebufferLimit
                if self.prebufferChunks[0].count <= excess {
                    self.prebufferBytes -= self.prebufferChunks[0].count
                    self.prebufferChunks.removeFirst()
                } else {
                    self.prebufferChunks[0].removeFirst(excess)
                    self.prebufferBytes -= excess
                }
            }

            self.firstFailurePrebufferChunks.append(data)
            self.firstFailurePrebufferBytes += data.count
            while self.firstFailurePrebufferBytes > self.firstFailurePrebufferLimit, !self.firstFailurePrebufferChunks.isEmpty {
                let excess = self.firstFailurePrebufferBytes - self.firstFailurePrebufferLimit
                if self.firstFailurePrebufferChunks[0].count <= excess {
                    self.firstFailurePrebufferBytes -= self.firstFailurePrebufferChunks[0].count
                    self.firstFailurePrebufferChunks.removeFirst()
                } else {
                    self.firstFailurePrebufferChunks[0].removeFirst(excess)
                    self.firstFailurePrebufferBytes -= excess
                }
            }

            var completed: [UUID] = []
            for (id, var window) in Array(self.activeWindows) {
                let amount = min(window.postBytesRemaining, data.count)
                if amount > 0 {
                    try? window.handle.write(contentsOf: data.prefix(amount))
                    window.postBytesRemaining -= amount
                }
                if window.postBytesRemaining <= 0 {
                    try? window.handle.synchronize()
                    try? window.handle.close()
                    completed.append(id)
                    self.writeTimeline(
                        category: "evidence",
                        message: "window_complete",
                        fields: ["label": window.label, "file": window.url.lastPathComponent]
                    )
                } else {
                    self.activeWindows[id] = window
                }
            }
            for id in completed { self.activeWindows.removeValue(forKey: id) }

            if var first = self.firstFailureWindow {
                let amount = min(first.postBytesRemaining, data.count)
                if amount > 0 {
                    try? first.handle.write(contentsOf: data.prefix(amount))
                    first.postBytesRemaining -= amount
                }
                if first.postBytesRemaining <= 0 {
                    try? first.handle.synchronize()
                    try? first.handle.close()
                    self.firstFailureCompleted = true
                    self.firstFailureWindow = nil
                    self.writeTimeline(
                        category: "first_failure",
                        message: "window_complete",
                        fields: ["label": first.label, "file": first.url.lastPathComponent]
                    )
                } else {
                    self.firstFailureWindow = first
                }
            }

            if self.totalRawBytes >= self.nextCheckpoint {
                self.writeTimeline(
                    category: "raw",
                    message: "checkpoint",
                    fields: [
                        "total_bytes": self.totalRawBytes,
                        "startup_bytes": self.startupBytes,
                        "active_windows": self.activeWindows.count,
                        "rolling_segment": self.rollingURL?.lastPathComponent ?? "none",
                        "rolling_segment_bytes": self.rollingSegmentBytes,
                        "chunk_bytes": data.count,
                        "chunk_fnv1a64": Self.fnv1a64(data),
                        "chunk_head64": Self.hexSample(data.prefix(64)),
                        "chunk_tail64": Self.hexSample(data.suffix(64))
                    ]
                )
                while self.nextCheckpoint <= self.totalRawBytes { self.nextCheckpoint &+= 4 * 1024 * 1024 }
            }
        }
    }

    /// Reserved once-per-session capture for the *first actual failure signal*.
    /// Unlike normal windows, this slot cannot be consumed by first-frame or
    /// collection-time events. It is also written to disk immediately so a later
    /// app/decoder failure cannot erase the evidence that preceded it.
    func triggerFirstFailureEvidence(_ label: String, detail: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.firstFailureTriggered else {
                self.writeTimeline(category: "first_failure", message: "already_reserved", fields: ["existing_label": self.firstFailureLabel, "ignored_label": label])
                return
            }
            self.firstFailureTriggered = true
            self.firstFailureLabel = label
            let safe = Self.safeFilename(label)
            let url = self.sessionDirectory.appendingPathComponent("FIRST_FAILURE_\(safe)_pre8MiB_post8MiB.h264")
            self.fileManager.createFile(atPath: url.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: url) else {
                self.writeTimeline(category: "first_failure", message: "file_open_failed", fields: ["label": label, "detail": detail])
                return
            }
            self.writeTail(self.firstFailurePrebufferChunks, maxBytes: self.firstFailurePrebufferLimit, to: handle)
            self.firstFailureWindow = ActiveWindow(label: label, url: url, handle: handle, postBytesRemaining: self.firstFailurePostbufferLimit)
            self.writeTimeline(
                category: "first_failure",
                message: "window_triggered",
                fields: [
                    "label": label,
                    "detail": detail,
                    "file": url.lastPathComponent,
                    "raw_offset": self.totalRawBytes,
                    "pre_bytes": min(self.firstFailurePrebufferBytes, self.firstFailurePrebufferLimit),
                    "post_target_bytes": self.firstFailurePostbufferLimit
                ]
            )
        }
    }

    /// Saves the last 4 MiB before a fault and the next 4 MiB after it.
    func triggerEvidenceWindow(_ label: String, detail: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.evidenceWindowCount < self.maximumEvidenceWindows else {
                self.droppedWindowCount += 1
                self.writeTimeline(
                    category: "evidence_drop",
                    message: "window_limit_reached",
                    fields: ["label": label, "detail": detail, "dropped": self.droppedWindowCount]
                )
                return
            }

            self.evidenceWindowCount += 1
            let ordinal = String(format: "%02d", self.evidenceWindowCount)
            let safe = Self.safeFilename(label)
            let url = self.sessionDirectory.appendingPathComponent("event_\(ordinal)_\(safe)_pre4MiB_post4MiB.h264")
            self.fileManager.createFile(atPath: url.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: url) else {
                self.writeTimeline(category: "evidence_drop", message: "file_open_failed", fields: ["label": label])
                return
            }
            self.writeTail(self.prebufferChunks, maxBytes: self.normalEvidencePrebufferLimit, to: handle)
            let id = UUID()
            self.activeWindows[id] = ActiveWindow(
                label: label,
                url: url,
                handle: handle,
                postBytesRemaining: self.postbufferLimit
            )
            self.writeTimeline(
                category: "evidence",
                message: "window_triggered",
                fields: [
                    "label": label,
                    "detail": detail,
                    "file": url.lastPathComponent,
                    "raw_offset": self.totalRawBytes,
                    "pre_bytes": min(self.prebufferBytes, self.normalEvidencePrebufferLimit),
                    "post_target_bytes": self.postbufferLimit
                ]
            )
        }
    }

    func captureImage(_ image: UIImage, label: String, quality: CGFloat = 0.82) {
        guard let data = image.jpegData(compressionQuality: quality) else { return }
        captureJPEG(data, label: label)
    }

    func captureJPEG(_ data: Data, label: String) {
        guard !data.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let safe = Self.safeFilename(label)
            guard !self.capturedLabels.contains(safe) else { return }
            self.capturedLabels.insert(safe)
            let url = self.imagesDirectory.appendingPathComponent("\(safe).jpg")
            do {
                try data.write(to: url, options: .atomic)
                self.writeTimeline(category: "image", message: "captured", fields: ["label": safe, "bytes": data.count])
            } catch {
                self.writeTimeline(category: "image", message: "write_failed", fields: ["label": safe, "error": error.localizedDescription])
            }
        }
    }

    /// Builds the shareable one-drive ZIP. External evidence is fetched by
    /// AppState only after the vehicle is parked, then injected here.
    func exportBundle(
        hudLogURL: URL?,
        summary: String,
        externalEvidence: [(name: String, data: Data)]
    ) throws -> URL {
        try queue.sync {
            writeTimeline(category: "export", message: "begin", fields: ["external_files": externalEvidence.count])

            if prebufferBytes > 0 {
                let tailURL = sessionDirectory.appendingPathComponent("raw_tail_last_4MiB.h264")
                fileManager.createFile(atPath: tailURL.path, contents: nil)
                if let tailHandle = try? FileHandle(forWritingTo: tailURL) {
                    writeTail(prebufferChunks, maxBytes: normalEvidencePrebufferLimit, to: tailHandle)
                    try? tailHandle.synchronize()
                    try? tailHandle.close()
                }
            }
            try summary.data(using: .utf8)?.write(
                to: sessionDirectory.appendingPathComponent("iphone_state.txt"),
                options: .atomic
            )
            if let hudLogURL, fileManager.fileExists(atPath: hudLogURL.path) {
                let target = sessionDirectory.appendingPathComponent("HUD_app_session.log")
                try? fileManager.removeItem(at: target)
                try fileManager.copyItem(at: hudLogURL, to: target)
            }

            let externalDir = sessionDirectory.appendingPathComponent("adapter", isDirectory: true)
            try fileManager.createDirectory(at: externalDir, withIntermediateDirectories: true)
            for item in externalEvidence {
                let target = externalDir.appendingPathComponent(Self.safeFilenamePreservingExtension(item.name))
                try item.data.write(to: target, options: .atomic)
            }

            for (_, window) in activeWindows { try? window.handle.synchronize() }
            try? firstFailureWindow?.handle.synchronize()
            try? rollingHandle?.synchronize()
            try? startupHandle?.synchronize()
            try? timelineHandle?.synchronize()

            let externalNames = externalEvidence.map(\.name).sorted()
            let completeness = """
            Live Map Diagnostic Completeness — v90.35.3.24.26
            ==================================================
            startup_capture_bytes=\(startupBytes)
            startup_capture_target_bytes=\(startupLimit)
            rolling_segments_retained=\(rollingSegments.count)
            rolling_segment_limit_bytes=\(rollingSegmentLimit)
            total_raw_tcp_bytes=\(totalRawBytes)
            first_failure_triggered=\(firstFailureTriggered ? "YES" : "NO")
            first_failure_label=\(firstFailureLabel)
            first_failure_complete=\(firstFailureCompleted ? "YES" : "NO")
            first_failure_active=\(firstFailureWindow == nil ? "NO" : "YES")
            normal_evidence_windows=\(evidenceWindowCount)
            normal_evidence_windows_dropped=\(droppedWindowCount)
            normal_evidence_windows_active=\(activeWindows.count)
            adapter_files_count=\(externalEvidence.count)
            adapter_files=\(externalNames.joined(separator: ","))

            Interpretation:
            - FIRST_FAILURE_* is a reserved 8 MiB pre/8 MiB post raw TCP window.
            - rolling_raw/ retains the newest bounded raw TCP segments even if the
              first failure happened long before parked collection.
            - timeline.jsonl contains raw-offset fingerprints plus parser/decoder
              state so the raw bytes can be aligned with VideoToolbox failures.
            """
            try Data(completeness.utf8).write(to: sessionDirectory.appendingPathComponent("COMPLETENESS_REPORT.txt"), options: .atomic)

            let manifest = """
            Live Map Diagnostic Bundle — HUD Controller v90.35.3.24.26
            ==========================================================
            Paired adapter: U2W v8.37 Forensic Seam Capture + unchanged v8.35 helper + unchanged v8.34 Hard-Bounded Mirror + exact v8.31 Raw Relay

            Purpose
            -------
            One normal drive should preserve enough synchronized evidence to separate:
            1. v8.11 AppleCarPlay mirror/source activation,
            2. U2W raw TCP/15332 transport,
            3. iPhone Annex-B/SPS/PPS/IDR parsing,
            4. VideoToolbox decode/recovery,
            5. app preview frame delivery,
            6. iPhone→U2W JPEG ingress / physical HUD rendering.

            Captures
            --------
            - timeline.jsonl: timestamped transport/parser/decoder/frame/fault events.
            - raw_startup_first_8MiB.h264: exact raw TCP bytes from startup.
            - FIRST_FAILURE_*.h264: reserved 8 MiB pre/8 MiB post first-fault window.
            - rolling_raw/: newest bounded raw TCP segments retained on disk.
            - event_*.h264: bounded ~4 MiB pre-fault + ~4 MiB post-fault windows.
            - raw_tail_last_4MiB.h264: final rolling raw context at collection time.
            - images/: first decoded frame, recovered frames, final preview/HUD JPEG when available.
            - HUD_app_session.log: normal production log for cross-correlation.
            - iphone_state.txt: final state/counters at collection.
            - adapter/: best-effort parked snapshots and passive diagnostic bundle if available.
            - COMPLETENESS_REPORT.txt: explicit evidence-presence report.

            Recorder statistics
            -------------------
            total_raw_bytes=\(totalRawBytes)
            startup_bytes=\(startupBytes)
            evidence_windows=\(evidenceWindowCount)
            evidence_windows_dropped=\(droppedWindowCount)
            incomplete_active_windows=\(activeWindows.count)
            first_failure_triggered=\(firstFailureTriggered)
            first_failure_complete=\(firstFailureCompleted)
            rolling_segments_retained=\(rollingSegments.count)

            Safety boundary
            ---------------
            The recorder does not signal/restart AppleCarPlay and does not alter U2W v8.31.
            Large adapter bundle collection is deferred until the user taps Collect after parking.
            The existing low-frequency passive source/topology observer may run during the drive.
            """
            try Data(manifest.utf8).write(to: sessionDirectory.appendingPathComponent("README_DIAGNOSTIC.txt"), options: .atomic)
            writeTimeline(category: "export", message: "snapshot_complete", fields: ["active_windows": activeWindows.count])
            try? timelineHandle?.synchronize()

            let parent = sessionDirectory.deletingLastPathComponent()
            let zipURL = parent.appendingPathComponent("LiveMap_Diagnostic_v90.35.3.24.26_\(Self.timestamp()).zip")
            try? fileManager.removeItem(at: zipURL)
            let writer = try LiveMapStoredZipWriter(url: zipURL)
            let files = try fileManager.subpathsOfDirectory(atPath: sessionDirectory.path)
                .sorted()
                .filter { !($0 as NSString).lastPathComponent.hasPrefix(".") }
            for relative in files {
                let url = sessionDirectory.appendingPathComponent(relative)
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                try writer.add(name: relative, fileURL: url)
            }
            try writer.finish()
            writeTimeline(category: "export", message: "zip_ready", fields: ["file": zipURL.lastPathComponent])
            return zipURL
        }
    }

    private func writeRollingRaw(_ data: Data) {
        var offset = 0
        while offset < data.count {
            if rollingHandle == nil || rollingSegmentBytes >= rollingSegmentLimit {
                try? rollingHandle?.synchronize()
                try? rollingHandle?.close()
                rollingSegmentSequence += 1
                rollingSegmentBytes = 0
                let start = totalRawBytes - UInt64(data.count - offset)
                let url = rollingDirectory.appendingPathComponent(String(format: "raw_roll_%04d_offset_%012llu.h264", rollingSegmentSequence, start))
                fileManager.createFile(atPath: url.path, contents: nil)
                rollingHandle = try? FileHandle(forWritingTo: url)
                rollingURL = url
                rollingSegments.append(url)
                while rollingSegments.count > maximumRollingSegments {
                    let old = rollingSegments.removeFirst()
                    try? fileManager.removeItem(at: old)
                }
                writeTimeline(category: "raw_roll", message: "segment_open", fields: ["file": url.lastPathComponent, "start_offset": start, "retained": rollingSegments.count])
            }
            guard let rollingHandle else { return }
            let room = rollingSegmentLimit - rollingSegmentBytes
            let amount = min(room, data.count - offset)
            let range = offset..<(offset + amount)
            try? rollingHandle.write(contentsOf: data.subdata(in: range))
            rollingSegmentBytes += amount
            offset += amount
        }
    }

    private func writeTail(_ chunks: [Data], maxBytes: Int, to handle: FileHandle) {
        var remaining = min(maxBytes, chunks.reduce(0) { $0 + $1.count })
        guard remaining > 0 else { return }
        var selected: [(Data, Int)] = []
        for chunk in chunks.reversed() {
            guard remaining > 0 else { break }
            let amount = min(remaining, chunk.count)
            selected.append((chunk, amount))
            remaining -= amount
        }
        for (chunk, amount) in selected.reversed() {
            try? handle.write(contentsOf: chunk.suffix(amount))
        }
    }

    private func writeTimeline(category: String, message: String, fields: [String: Any]) {
        var object: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "uptime": ProcessInfo.processInfo.systemUptime,
            "category": category,
            "message": message,
            "raw_offset": totalRawBytes
        ]
        for (key, value) in fields { object[key] = value }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        var line = data
        line.append(0x0A)
        try? timelineHandle?.write(contentsOf: line)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }

    private static func hexSample<C: Collection>(_ bytes: C) -> String where C.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func fnv1a64(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private static func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let pieces = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }
        let result = pieces.joined().replacingOccurrences(of: "__", with: "_")
        return String(result.prefix(72))
    }

    private static func safeFilenamePreservingExtension(_ value: String) -> String {
        let ns = value as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        let safeStem = safeFilename(stem)
        return ext.isEmpty ? safeStem : "\(safeStem).\(safeFilename(ext))"
    }
}

final class LiveMapStoredZipWriter {
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

    deinit { if !finished { try? handle.close() } }

    func add(name: String, fileURL: URL) throws {
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let nameData = Data(name.utf8)
        let crc = LiveMapCRC32.checksum(data)
        guard data.count <= Int(UInt32.max) else {
            throw NSError(domain: "LiveMapDiagnosticZIP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Diagnostic file is too large for ZIP32"])
        }
        let size = UInt32(data.count)
        let localOffset = offset

        var header = Data()
        header.liveMapAppendLE(0x04034b50)
        header.liveMapAppendLE16(20)
        header.liveMapAppendLE16(0)
        header.liveMapAppendLE16(0)
        header.liveMapAppendLE16(0)
        header.liveMapAppendLE16(0)
        header.liveMapAppendLE(crc)
        header.liveMapAppendLE(size)
        header.liveMapAppendLE(size)
        header.liveMapAppendLE16(UInt16(nameData.count))
        header.liveMapAppendLE16(0)
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
            central.liveMapAppendLE(0x02014b50)
            central.liveMapAppendLE16(20)
            central.liveMapAppendLE16(20)
            central.liveMapAppendLE16(0)
            central.liveMapAppendLE16(0)
            central.liveMapAppendLE16(0)
            central.liveMapAppendLE16(0)
            central.liveMapAppendLE(entry.crc32)
            central.liveMapAppendLE(entry.size)
            central.liveMapAppendLE(entry.size)
            central.liveMapAppendLE16(UInt16(entry.name.count))
            central.liveMapAppendLE16(0)
            central.liveMapAppendLE16(0)
            central.liveMapAppendLE16(0)
            central.liveMapAppendLE16(0)
            central.liveMapAppendLE(0)
            central.liveMapAppendLE(entry.localOffset)
            central.append(entry.name)
        }
        try handle.write(contentsOf: central)
        offset &+= UInt32(central.count)

        var end = Data()
        end.liveMapAppendLE(0x06054b50)
        end.liveMapAppendLE16(0)
        end.liveMapAppendLE16(0)
        end.liveMapAppendLE16(UInt16(entries.count))
        end.liveMapAppendLE16(UInt16(entries.count))
        end.liveMapAppendLE(UInt32(central.count))
        end.liveMapAppendLE(centralOffset)
        end.liveMapAppendLE16(0)
        try handle.write(contentsOf: end)
        try handle.synchronize()
        try handle.close()
        finished = true
    }
}

private enum LiveMapCRC32 {
    static let table: [UInt32] = (0..<256).map { raw in
        var c = UInt32(raw)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : (c >> 1) }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func liveMapAppendLE(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }

    mutating func liveMapAppendLE16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }
}

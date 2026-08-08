import Foundation
import Observation

@MainActor
@Observable
final class LogManager {
    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let category: String
        let message: String
    }

    private(set) var entries: [Entry] = []
    private(set) var currentFileURL: URL?

    init() {
        startSession()
    }

    private var logDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("HUDWAY Logs", isDirectory: true)
    }

    func startSession() {
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        currentFileURL = logDirectory.appendingPathComponent("HUDWAY_\(formatter.string(from: Date())).log")
        log("APP", "Session started")
    }

    func log(_ category: String, _ message: String) {
        let entry = Entry(date: Date(), category: category, message: message)
        entries.append(entry)
        let iso = ISO8601DateFormatter().string(from: entry.date)
        let line = "\(iso)  \(category.padding(toLength: 12, withPad: " ", startingAt: 0)) \(message)\n"
        guard let url = currentFileURL, let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    func logFiles() -> [URL] {
        let files = try? FileManager.default.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        return files?
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
    }

    func clearVisibleEntries() {
        entries.removeAll()
        log("APP", "Visible log cleared")
    }
}

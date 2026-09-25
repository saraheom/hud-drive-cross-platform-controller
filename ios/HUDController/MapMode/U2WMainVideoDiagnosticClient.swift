import Foundation
import Observation

/// v90.35.3.24.11 passive U2W MainVideo lifecycle diagnostic.
///
/// This client never starts Map Mode and never talks to AppleCarPlay directly.
/// It only asks the adapter's v8.27.1 read-only diagnostic CGI to start a
/// low-frequency /proc sampler, capture explicit snapshots, or package a bounded
/// diagnostic bundle after the drive.
@MainActor
@Observable
final class U2WMainVideoDiagnosticClient {
    private(set) var status = "Passive probe not started"
    private(set) var bundleURL: URL?
    private(set) var lastSnapshotStatus = "No manual snapshot"
    private(set) var collecting = false

    private let logger: LogManager
    private let startEndpoint = URL(string: "http://192.168.50.2/cgi-bin/u2wvideo-diag-start.cgi")!
    private let statusEndpoint = URL(string: "http://192.168.50.2/cgi-bin/u2wvideo-diag-status.cgi")!
    private let markEndpoint = URL(string: "http://192.168.50.2/cgi-bin/u2wvideo-diag-mark.cgi")!
    private let bundleEndpoint = URL(string: "http://192.168.50.2/cgi-bin/u2wvideo-diag-bundle.cgi")!
    private var lastEnsureAt = Date.distantPast
    private let ensureCooldown: TimeInterval = 30

    init(logger: LogManager) {
        self.logger = logger
    }

    func ensureStarted(reason: String) {
        let now = Date()
        guard now.timeIntervalSince(lastEnsureAt) >= ensureCooldown else { return }
        lastEnsureAt = now
        Task { @MainActor [weak self] in
            await self?.startProbe(reason: reason)
        }
    }

    func refreshStatus() {
        Task { @MainActor [weak self] in
            await self?.loadStatus()
        }
    }

    func captureSnapshot() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let text = try await self.fetchText(self.markEndpoint, timeout: 5)
                self.lastSnapshotStatus = text.isEmpty ? "Snapshot captured" : text
                self.logger.log("U2W PASSIVE", "Manual topology snapshot: \(text.replacingOccurrences(of: "\n", with: " | "))")
            } catch {
                self.lastSnapshotStatus = "Snapshot failed: \(error.localizedDescription)"
                self.logger.log("U2W PASSIVE", "Manual topology snapshot failed: \(error.localizedDescription)")
            }
        }
    }

    func collectBundle() {
        guard !collecting else { return }
        collecting = true
        status = "Collecting passive U2W diagnostic bundle…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.collecting = false }
            do {
                var request = URLRequest(url: self.bundleEndpoint)
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                request.timeoutInterval = 30
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 30
                configuration.timeoutIntervalForResource = 45
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      data.count > 32 else {
                    throw URLError(.badServerResponse)
                }

                let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("U2W Diagnostics", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let url = directory.appendingPathComponent("U2W_MainVideo_Diagnostic_\(formatter.string(from: Date())).tar.gz")
                try data.write(to: url, options: .atomic)
                self.bundleURL = url
                self.status = "Bundle ready • \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
                self.logger.log("U2W PASSIVE", "Saved MainVideo diagnostic bundle \(url.lastPathComponent) bytes=\(data.count)")
                await self.loadStatus()
            } catch {
                self.status = "Bundle collection failed: \(error.localizedDescription)"
                self.logger.log("U2W PASSIVE", "Diagnostic bundle collection failed: \(error.localizedDescription)")
            }
        }
    }

    private func startProbe(reason: String) async {
        do {
            let text = try await fetchText(startEndpoint, timeout: 5)
            status = text.isEmpty ? "Passive probe started" : text
            logger.log("U2W PASSIVE", "Probe ensure reason=\(reason) response={\(text.replacingOccurrences(of: "\n", with: " | "))}")
            await loadStatus()
        } catch {
            status = "Passive probe unavailable"
            logger.log("U2W PASSIVE", "Probe ensure failed reason=\(reason): \(error.localizedDescription)")
        }
    }

    private func loadStatus() async {
        do {
            let text = try await fetchText(statusEndpoint, timeout: 4)
            let compact = text
                .split(separator: "\n")
                .prefix(5)
                .joined(separator: " • ")
            status = compact.isEmpty ? "Passive probe reachable" : compact
            logger.log("U2W PASSIVE", "Status {\(text.replacingOccurrences(of: "\n", with: " | "))}")
        } catch {
            status = "Passive probe status unavailable"
            logger.log("U2W PASSIVE", "Status failed: \(error.localizedDescription)")
        }
    }

    private func fetchText(_ url: URL, timeout: TimeInterval) async throws -> String {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeout
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 2
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

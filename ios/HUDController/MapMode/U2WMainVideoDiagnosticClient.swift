import Foundation
import Observation

/// v90.35.3.24.12 automatic passive U2W MainVideo codec diagnostic.
///
/// The app automatically asks U2W v8.27.2 to start both the low-frequency
/// topology sampler and a separate read-only H.264 codec observer when the
/// adapter becomes reachable. Neither observer enables Map Mode or talks to
/// AppleCarPlay directly. During the drive no user action is required. After
/// parking, one bundle request packages the whole automatic timeline, bounded
/// gap/recovery byte captures, topology state, and final mirror tail.
@MainActor
@Observable
final class U2WMainVideoDiagnosticClient {
    private(set) var status = "Automatic codec probe starts with CarPlay"
    private(set) var bundleURL: URL?
    private(set) var collecting = false

    private let logger: LogManager
    private let startEndpoint = URL(string: "http://192.168.50.2/cgi-bin/u2wvideo-diag-start.cgi")!
    private let statusEndpoint = URL(string: "http://192.168.50.2/cgi-bin/u2wvideo-diag-status.cgi")!
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

    func restartProbe() {
        lastEnsureAt = .distantPast
        ensureStarted(reason: "manual restart")
    }

    func refreshStatus() {
        Task { @MainActor [weak self] in
            await self?.loadStatus()
        }
    }

    func collectBundle() {
        guard !collecting else { return }
        collecting = true
        status = "Collecting automatic codec diagnostic bundle…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.collecting = false }
            do {
                var request = URLRequest(url: self.bundleEndpoint)
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                request.timeoutInterval = 75
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 75
                configuration.timeoutIntervalForResource = 90
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
                let url = directory.appendingPathComponent("U2W_MainVideo_Codec_Diagnostic_\(formatter.string(from: Date())).tar.gz")
                try data.write(to: url, options: .atomic)
                self.bundleURL = url
                self.status = "Bundle ready • \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
                self.logger.log("U2W CODEC", "Saved automatic MainVideo codec diagnostic bundle \(url.lastPathComponent) bytes=\(data.count)")
                await self.loadStatus()
            } catch {
                self.status = "Bundle collection failed: \(error.localizedDescription)"
                self.logger.log("U2W CODEC", "Automatic diagnostic bundle collection failed: \(error.localizedDescription)")
            }
        }
    }

    private func startProbe(reason: String) async {
        do {
            let text = try await fetchText(startEndpoint, timeout: 6)
            status = text.isEmpty ? "Automatic codec probe started" : text
            logger.log("U2W CODEC", "Automatic probe ensure reason=\(reason) response={\(text.replacingOccurrences(of: "\n", with: " | "))}")
            await loadStatus()
        } catch {
            status = "Automatic codec probe unavailable"
            logger.log("U2W CODEC", "Automatic probe ensure failed reason=\(reason): \(error.localizedDescription)")
        }
    }

    private func loadStatus() async {
        do {
            let text = try await fetchText(statusEndpoint, timeout: 5)
            let lines = text.split(separator: "\n")
            let interesting = lines.filter { line in
                line.hasPrefix("codec_probe=") ||
                line.hasPrefix("codec_state=") ||
                line.hasPrefix("codec_valid_idr_access_units=") ||
                line.hasPrefix("codec_valid_p_access_units=") ||
                line.hasPrefix("codec_seconds_since_valid_au=") ||
                line.hasPrefix("codec_gap_events=") ||
                line.hasPrefix("codec_recovery_events=") ||
                line.hasPrefix("applecarplay_pid=")
            }
            let compact = (interesting.isEmpty ? Array(lines.prefix(6)) : Array(interesting.prefix(8)))
                .joined(separator: " • ")
            status = compact.isEmpty ? "Automatic codec probe reachable" : compact
            logger.log("U2W CODEC", "Status {\(text.replacingOccurrences(of: "\n", with: " | "))}")
        } catch {
            status = "Automatic codec probe status unavailable"
            logger.log("U2W CODEC", "Status failed: \(error.localizedDescription)")
        }
    }

    private func fetchText(_ url: URL, timeout: TimeInterval) async throws -> String {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeout
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 3
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

import Foundation
import Observation

/// Passive CarPlay Now Playing client backed by U2W v8.6.
///
/// Unlike navigation, an unchanged media sequence is normal (for example while
/// paused). HTTP reachability and the explicit playback state are therefore
/// kept separate from sequence progression.
@MainActor
@Observable
final class CarPlayNowPlayingClient {
    struct Snapshot: Codable, Equatable {
        var version: Int
        var sequence: Int
        var receivedUpdates: Int
        var sourceApp: String
        var sourceBundleID: String
        var playbackStatus: Int
        var playing: Bool
        var title: String
        var artist: String
        var album: String
        var durationMs: Int
        var elapsedMs: Int
        var queueIndex: Int
        var queueCount: Int
        var trackNumber: Int
        var trackCount: Int
        var shuffleMode: Int
        var repeatMode: Int
        var artworkTransferID: Int
        var artworkSequence: Int
        var artworkBytes: Int
        var artworkAvailable: Bool
        var artworkURL: String
    }

    private let logger: LogManager
    private let endpoint = URL(string: "http://192.168.50.2/cgi-bin/u2wmedia-live.cgi")!
    private let artworkEndpoint = URL(string: "http://192.168.50.2/cgi-bin/u2wmedia-artwork.cgi")!
    private let pollInterval: Duration = .milliseconds(750)
    private var pollTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var lastTrackSignature = ""
    private var lastArtworkSequence = -1
    private var lastArtworkTransferID = -1
    private var requestCounter = 0

    var onTrackChanged: ((String, String) -> Void)?

    private(set) var running = false
    private(set) var reachable = false
    private(set) var status = "CarPlay Now Playing idle"
    private(set) var sourceApp = "—"
    private(set) var sourceBundleID = ""
    private(set) var playbackStatus = 0
    private(set) var title = "No CarPlay media"
    private(set) var artist = ""
    private(set) var album = ""
    private(set) var durationMs = 0
    private(set) var elapsedMs = 0
    private(set) var artworkData: Data?
    private(set) var lastUpdateAt: Date?
    private(set) var lastError = ""
    private(set) var sequence = 0

    init(logger: LogManager) {
        self.logger = logger
    }

    var playbackDescription: String {
        switch playbackStatus {
        case 1: "Playing"
        case 2: "Paused"
        case 3: "Seeking forward"
        case 4: "Seeking backward"
        default: title == "No CarPlay media" ? "Stopped" : "Stopped"
        }
    }

    func start(reason: String) {
        guard pollTask == nil else { return }
        running = true
        status = "Connecting to U2W Now Playing…"
        logger.log("CARPLAY MEDIA", "Polling started reason=\(reason) endpoint=\(endpoint.absoluteString)")
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    func stop(reason: String) {
        pollTask?.cancel(); pollTask = nil
        artworkTask?.cancel(); artworkTask = nil
        running = false
        reachable = false
        status = "CarPlay Now Playing stopped"
        logger.log("CARPLAY MEDIA", "Polling stopped reason=\(reason)")
    }

    func refreshNow() {
        start(reason: "manual refresh")
        Task { @MainActor [weak self] in await self?.pollOnce() }
    }

    private func pollOnce() async {
        requestCounter += 1
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 1.5
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            reachable = true
            lastError = ""
            lastUpdateAt = Date()
            ingest(snapshot)
        } catch {
            reachable = false
            lastError = error.localizedDescription
            status = "U2W Now Playing unavailable"
            if requestCounter <= 3 || requestCounter % 20 == 0 {
                logger.log("CARPLAY MEDIA", "Poll failed request=\(requestCounter): \(error.localizedDescription)")
            }
        }
    }

    private func ingest(_ snapshot: Snapshot) {
        sequence = snapshot.sequence
        sourceApp = snapshot.sourceApp.isEmpty ? "—" : snapshot.sourceApp
        sourceBundleID = snapshot.sourceBundleID
        playbackStatus = snapshot.playbackStatus
        durationMs = max(0, snapshot.durationMs)
        elapsedMs = max(0, snapshot.elapsedMs)
        title = snapshot.title.isEmpty ? "No CarPlay media" : snapshot.title
        artist = snapshot.artist
        album = snapshot.album
        status = snapshot.title.isEmpty
            ? "CarPlay connected • waiting for media"
            : "\(playbackDescription) • \(sourceApp)"

        let trackSignature = "\(snapshot.sourceBundleID)|\(snapshot.title)|\(snapshot.artist)|\(snapshot.album)"
        if !snapshot.title.isEmpty, trackSignature != lastTrackSignature {
            lastTrackSignature = trackSignature
            logger.log("CARPLAY MEDIA", "Track \(snapshot.sourceApp): \(snapshot.artist) — \(snapshot.title)")
            onTrackChanged?(snapshot.artist, snapshot.title)
        }

        if snapshot.artworkTransferID != lastArtworkTransferID {
            lastArtworkTransferID = snapshot.artworkTransferID
            // Do not show artwork from the previous track while the new JPEG is
            // still transferring on iAP2.
            artworkData = nil
        }
        if snapshot.artworkAvailable,
           snapshot.artworkSequence != lastArtworkSequence {
            lastArtworkSequence = snapshot.artworkSequence
            fetchArtwork(sequence: snapshot.artworkSequence)
        }
    }

    private func fetchArtwork(sequence: Int) {
        artworkTask?.cancel()
        artworkTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var request = URLRequest(url: self.artworkEndpoint)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 2.0
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled,
                      let http = response as? HTTPURLResponse,
                      http.statusCode == 200,
                      data.count >= 4,
                      data[0] == 0xFF, data[1] == 0xD8 else { return }
                self.artworkData = data
                self.logger.log("CARPLAY MEDIA ART", "Artwork seq=\(sequence) bytes=\(data.count)")
            } catch {
                if !Task.isCancelled {
                    self.logger.log("CARPLAY MEDIA ART", "Artwork fetch failed seq=\(sequence): \(error.localizedDescription)")
                }
            }
        }
    }
}

import Foundation
import Observation
import SpotifyiOS
import UserNotifications

@MainActor
@Observable
final class SpotifyMediaController: NSObject {
    private(set) var connected = false
    private(set) var authorized = false
    private(set) var trackTitle = "No Spotify track"
    private(set) var artistName = ""
    private(set) var status = "Not connected"

    private let logger: LogManager
    private var lastNotifiedTrackURI: String?

    private lazy var configuration: SPTConfiguration = {
        let clientID = Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_CLIENT_ID") as? String ?? ""
        let redirectString = Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_REDIRECT_URI") as? String
            ?? "jjunnyy-hud-login://spotify-callback"

        return SPTConfiguration(
            clientID: clientID,
            redirectURL: URL(string: redirectString)!
        )
    }()

    private lazy var appRemote: SPTAppRemote = {
        let remote = SPTAppRemote(configuration: configuration, logLevel: .debug)
        remote.delegate = self
        return remote
    }()

    init(logger: LogManager) {
        self.logger = logger
        super.init()
    }

    var isConfigured: Bool {
        !configuration.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                if let error {
                    self.logger.log("MEDIA ERROR", "Notification permission: \(error.localizedDescription)")
                } else {
                    self.logger.log("MEDIA", "Local notification permission = \(granted)")
                }
            }
        }
    }

    func connectOrAuthorize() {
        requestNotificationPermission()

        guard isConfigured else {
            status = "Spotify Client ID is not configured"
            logger.log("MEDIA ERROR", status)
            return
        }

        if appRemote.connectionParameters.accessToken != nil {
            status = "Connecting to Spotify…"
            logger.log("MEDIA", "Connecting to Spotify App Remote")
            appRemote.connect()
            return
        }

        status = "Opening Spotify authorization…"
        logger.log("MEDIA", "Starting Spotify App Remote authorization")

        appRemote.authorizeAndPlayURI("") { installed in
            Task { @MainActor in
                self.logger.log("MEDIA", "Spotify installed = \(installed)")
                if !installed {
                    self.status = "Spotify app is not installed"
                }
            }
        }
    }

    func disconnect() {
        appRemote.disconnect()
        connected = false
        status = "Disconnected"
    }

    func handleCallback(_ url: URL) -> Bool {
        guard url.scheme == "jjunnyy-hud-login" else { return false }

        let parameters = appRemote.authorizationParameters(from: url)

        if let token = parameters?[SPTAppRemoteAccessTokenKey] {
            appRemote.connectionParameters.accessToken = token
            authorized = true
            status = "Authorized; connecting…"
            logger.log("MEDIA", "Spotify authorization callback received")
            appRemote.connect()
            return true
        }

        if let error = parameters?[SPTAppRemoteErrorDescriptionKey] {
            status = "Spotify authorization error"
            logger.log("MEDIA ERROR", error)
            return true
        }

        return false
    }

    func sendMediaTestNotification() {
        postHUDNotification(
            title: "Now Playing",
            body: "HUD media bridge test"
        )
    }

    private func postHUDNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "hud.media.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            Task { @MainActor in
                if let error {
                    self.logger.log("MEDIA ERROR", "Local notification failed: \(error.localizedDescription)")
                } else {
                    self.logger.log("MEDIA HUD", "\(title): \(body)")
                }
            }
        }
    }

    private func notifyTrackIfChanged(_ playerState: SPTAppRemotePlayerState) {
        let track = playerState.track
        trackTitle = track.name
        artistName = track.artist.name

        guard track.uri != lastNotifiedTrackURI else { return }
        lastNotifiedTrackURI = track.uri

        logger.log("MEDIA", "Spotify track: \(artistName) — \(trackTitle)")

        postHUDNotification(
            title: "Now Playing",
            body: "\(artistName) — \(trackTitle)"
        )
    }
}

extension SpotifyMediaController: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
            self.connected = true
            self.status = "Spotify connected"
            self.logger.log("MEDIA", "Spotify App Remote connected")

            appRemote.playerAPI?.delegate = self
            appRemote.playerAPI?.subscribe(toPlayerState: { _, error in
                Task { @MainActor in
                    if let error {
                        self.logger.log("MEDIA ERROR", "Player-state subscription: \(error.localizedDescription)")
                    } else {
                        self.logger.log("MEDIA", "Subscribed to Spotify player state")
                    }
                }
            })
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote,
                               didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor in
            self.connected = false
            self.status = "Spotify connection failed"
            self.logger.log(
                "MEDIA ERROR",
                error?.localizedDescription ?? "Unknown Spotify connection error"
            )
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote,
                               didDisconnectWithError error: Error?) {
        Task { @MainActor in
            self.connected = false
            self.status = "Spotify disconnected"
            self.logger.log(
                "MEDIA",
                "Spotify disconnected: \(error?.localizedDescription ?? "no error")"
            )
        }
    }
}

extension SpotifyMediaController: SPTAppRemotePlayerStateDelegate {
    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        Task { @MainActor in
            self.notifyTrackIfChanged(playerState)
        }
    }
}

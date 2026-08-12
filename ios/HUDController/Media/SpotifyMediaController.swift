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
    private var reconnectTask: Task<Void, Never>?
    private var userRequestedDisconnect = false
    var onTrackChanged: ((String, String) -> Void)?

    @ObservationIgnored
    private lazy var configuration: SPTConfiguration = {
        let clientID = Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_CLIENT_ID") as? String ?? ""
        let redirectString = Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_REDIRECT_URI") as? String
            ?? "jjunnyy-hud-login://spotify-callback"

        return SPTConfiguration(
            clientID: clientID,
            redirectURL: URL(string: redirectString)!
        )
    }()

    @ObservationIgnored
    private lazy var appRemote: SPTAppRemote = {
        let remote = SPTAppRemote(configuration: configuration, logLevel: .debug)
        remote.delegate = self
        return remote
    }()

    init(logger: LogManager) {
        self.logger = logger
        super.init()

        if let token = SpotifyTokenStore.load() {
            appRemote.connectionParameters.accessToken = token
            authorized = true
            status = "Previously authorized"
            logger.log("MEDIA AUTO", "Restored Spotify App Remote token from Keychain")
        }
    }

    var isConfigured: Bool {
        !configuration.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func autoConnectIfPossible() {
        userRequestedDisconnect = false

        guard isConfigured else {
            logger.log("MEDIA AUTO", "Spotify auto-connect skipped: Client ID missing")
            return
        }
        guard !connected else { return }

        guard let token = appRemote.connectionParameters.accessToken, !token.isEmpty else {
            logger.log("MEDIA AUTO", "No saved Spotify authorization; one-time manual authorization required")
            return
        }

        reconnectTask?.cancel()
        reconnectTask = nil
        status = "Connecting to Spotify automatically…"
        logger.log("MEDIA AUTO", "Attempting Spotify App Remote auto-connect")
        appRemote.connect()
    }

    func appBecameActive() {
        guard !connected else { return }
        autoConnectIfPossible()
    }

    func appEnteredBackground() {
        reconnectTask?.cancel()
        reconnectTask = nil
        logger.log("MEDIA AUTO", "App backgrounded; preserving Spotify App Remote state")
    }


private func scheduleReconnect() {
    // Deliberately do not spin forever. App Remote failures often mean
    // Spotify needs a fresh user authorization/open-app transition.
    guard !userRequestedDisconnect else { return }
    guard reconnectTask == nil else { return }
    reconnectTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(8))
        guard let self, !Task.isCancelled, !self.connected else { return }
        self.reconnectTask = nil
        self.logger.log("MEDIA AUTO", "One delayed Spotify reconnect attempt")
        self.appRemote.connect()
    }
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
        userRequestedDisconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil

        guard isConfigured else {
            status = "Spotify Client ID is not configured"
            logger.log("MEDIA ERROR", status)
            return
        }

        // This button is intentionally "Re-authorize", not merely connect.
        // A stale Keychain token was causing every manual tap to repeat the
        // same failed appRemote.connect() call without reopening Spotify.
        appRemote.disconnect()
        appRemote.connectionParameters.accessToken = nil
        SpotifyTokenStore.clear()
        authorized = false

        status = "Opening Spotify authorization…"
        logger.log("MEDIA", "Starting fresh Spotify App Remote authorization")

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
        userRequestedDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        appRemote.disconnect()
        connected = false
        status = "Disconnected"
        logger.log("MEDIA", "User disconnected Spotify; auto-reconnect paused")
    }

    func handleCallback(_ url: URL) -> Bool {
        guard url.scheme == "jjunnyy-hud-login" else { return false }

        let parameters = appRemote.authorizationParameters(from: url)

        if let token = parameters?[SPTAppRemoteAccessTokenKey] {
            appRemote.connectionParameters.accessToken = token
            SpotifyTokenStore.save(token)
            authorized = true
            status = "Authorized; connecting…"
            logger.log("MEDIA", "Spotify authorization callback received; token saved to Keychain")
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
        onTrackChanged?(artistName, trackTitle)
    }
}

extension SpotifyMediaController: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
            self.reconnectTask?.cancel()
            self.reconnectTask = nil
            self.userRequestedDisconnect = false
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
            self.status = "Spotify connection unavailable"
            let nsError = error as NSError?
            self.logger.log(
                "MEDIA ERROR",
                "Spotify connect failed domain=\(nsError?.domain ?? "nil") code=\(nsError?.code ?? -1) description=\(error?.localizedDescription ?? "unknown")"
            )
            self.scheduleReconnect()
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
            self.scheduleReconnect()
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

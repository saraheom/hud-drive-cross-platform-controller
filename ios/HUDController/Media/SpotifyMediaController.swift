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
    private var reconnectAttempt = 0
    private var userRequestedDisconnect = false
    private(set) var authorizationRequired = false
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
            authorizationRequired = false
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
            status = "Spotify Client ID is not configured"
            logger.log("MEDIA AUTO", "Spotify auto-connect skipped: Client ID missing")
            return
        }

        guard !connected else {
            reconnectAttempt = 0
            return
        }

        guard let token = appRemote.connectionParameters.accessToken,
              !token.isEmpty else {
            authorized = false
            authorizationRequired = true
            status = "Spotify authorization required"
            logger.log(
                "MEDIA AUTO",
                "No saved Spotify authorization; one-time authorization required"
            )
            return
        }

        authorized = true
        authorizationRequired = false

        reconnectTask?.cancel()
        reconnectTask = nil
        status = reconnectAttempt == 0
            ? "Connecting to Spotify automatically…"
            : "Reconnecting to Spotify automatically…"

        logger.log(
            "MEDIA AUTO",
            "Attempting Spotify App Remote connection attempt=\(reconnectAttempt + 1)"
        )
        appRemote.connect()
    }

    func appBecameActive() {
        guard !connected else { return }
        userRequestedDisconnect = false
        autoConnectIfPossible()
    }

    func appEnteredBackground() {
        // Do not clear authorization or mark this as a user disconnect.
        // iOS may suspend the retry timer, but the next active transition
        // immediately resumes automatic connection.
        logger.log("MEDIA AUTO", "App backgrounded; preserving Spotify authorization/reconnect intent")
    }

    private func scheduleReconnect(reason: String) {
        guard !userRequestedDisconnect else { return }
        guard !authorizationRequired else { return }
        guard authorized else { return }
        guard reconnectTask == nil else { return }

        let delays: [Double] = [2, 5, 10, 15]
        let delay = delays[min(reconnectAttempt, delays.count - 1)]
        reconnectAttempt += 1

        status = "Spotify reconnecting automatically…"
        logger.log(
            "MEDIA AUTO",
            "Scheduling reconnect in \(Int(delay))s reason=\(reason) attempt=\(reconnectAttempt)"
        )

        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled,
                  !self.connected,
                  !self.userRequestedDisconnect,
                  !self.authorizationRequired else { return }

            self.reconnectTask = nil
            self.autoConnectIfPossible()
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

    /// Normal entry point. If a saved authorization exists, this never
    /// clears it and simply reconnects. Only a genuinely unauthorized state
    /// enters Spotify's one-time authorization flow.
    func connectOrAuthorize() {
        userRequestedDisconnect = false

        guard isConfigured else {
            status = "Spotify Client ID is not configured"
            logger.log("MEDIA ERROR", status)
            return
        }

        if let token = appRemote.connectionParameters.accessToken,
           !token.isEmpty {
            authorized = true
            authorizationRequired = false
            reconnectAttempt = 0
            autoConnectIfPossible()
            return
        }

        beginAuthorization()
    }

    /// Explicit troubleshooting action. This is the only normal UI path that
    /// intentionally discards the stored Spotify authorization token.
    func reauthorize() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0

        appRemote.disconnect()
        appRemote.connectionParameters.accessToken = nil
        SpotifyTokenStore.clear()
        connected = false
        authorized = false
        authorizationRequired = true

        beginAuthorization()
    }

    private func beginAuthorization() {
        guard isConfigured else {
            status = "Spotify Client ID is not configured"
            return
        }

        userRequestedDisconnect = false
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
        userRequestedDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
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
            authorizationRequired = false
            reconnectAttempt = 0
            status = "Authorized; connecting…"
            logger.log("MEDIA", "Spotify authorization callback received; token saved to Keychain")
            appRemote.connect()
            return true
        }

        if let error = parameters?[SPTAppRemoteErrorDescriptionKey] {
            authorized = false
            authorizationRequired = true
            status = "Spotify authorization required"
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
            self.reconnectAttempt = 0
            self.authorizationRequired = false
            self.authorized = true
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
            self.scheduleReconnect(reason: error?.localizedDescription ?? "connection attempt failed")
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
            self.scheduleReconnect(reason: error?.localizedDescription ?? "unexpected disconnect")
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

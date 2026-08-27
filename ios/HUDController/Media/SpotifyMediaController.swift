import Foundation
import Observation
import SpotifyiOS
import UserNotifications
import UIKit

@MainActor
@Observable
final class SpotifyMediaController: NSObject {
    private(set) var connected = false
    private(set) var authorized = false
    private(set) var trackTitle = "No Spotify track"
    private(set) var artistName = ""
    private(set) var status = "Not connected"
    private(set) var authorizationRequired = false
    private(set) var automaticRecoveryActive = false
    private(set) var automaticVehicleWakeAllowed = false

    private let logger: LogManager
    private var lastNotifiedTrackURI: String?

    private var reconnectTask: Task<Void, Never>?
    private var subscriptionRetryTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var consecutiveConnectionFailures = 0
    private var remoteGeneration = 0
    private var reconnectGeneration = 0
    private var connectionInFlight = false
    private var userRequestedDisconnect = false
    private var automaticWakeInProgress = false
    private var lastAutomaticWakeAt: Date?
    private var automaticWakeFallbackTask: Task<Void, Never>?
    private let automaticWakeCooldown: TimeInterval = 45

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

    // Intentionally replaceable. Field testing showed that a long-lived
    // SPTAppRemote can remain stuck returning -1000 even though the saved
    // authorization is still valid. A fresh object with the same Keychain
    // token can connect immediately.
    @ObservationIgnored
    private var appRemote: SPTAppRemote!

    init(logger: LogManager) {
        self.logger = logger
        super.init()

        rebuildAppRemote(reason: "controller initialization")

        if restoreTokenFromKeychain() {
            status = "Previously authorized"
        }
    }

    var isConfigured: Bool {
        !configuration.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func makeRemote() -> SPTAppRemote {
        let remote = SPTAppRemote(configuration: configuration, logLevel: .debug)
        remote.delegate = self
        return remote
    }

    @discardableResult
    private func restoreTokenFromKeychain() -> Bool {
        guard let token = SpotifyTokenStore.load(), !token.isEmpty else {
            authorized = false
            authorizationRequired = true
            return false
        }

        appRemote.connectionParameters.accessToken = token
        authorized = true
        authorizationRequired = false
        logger.log("MEDIA AUTO", "Restored Spotify App Remote token from Keychain")
        return true
    }

    private func rebuildAppRemote(reason: String) {
        reconnectTask?.cancel()
        reconnectTask = nil
        subscriptionRetryTask?.cancel()
        subscriptionRetryTask = nil
        connectionInFlight = false

        let preservedToken =
            SpotifyTokenStore.load() ??
            appRemote?.connectionParameters.accessToken

        if let oldRemote = appRemote {
            oldRemote.delegate = nil
            if oldRemote.isConnected {
                oldRemote.disconnect()
            }
        }

        remoteGeneration += 1
        let freshRemote = makeRemote()
        if let preservedToken, !preservedToken.isEmpty {
            freshRemote.connectionParameters.accessToken = preservedToken
        }
        appRemote = freshRemote

        logger.log(
            "MEDIA AUTO",
            "Created fresh Spotify App Remote generation=\(remoteGeneration) reason=\(reason)"
        )
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
            consecutiveConnectionFailures = 0
            automaticRecoveryActive = false
            ensurePlayerStateSubscription()
            return
        }

        guard !connectionInFlight else {
            logger.log("MEDIA AUTO", "Connect suppressed: Spotify connection already in flight")
            return
        }

        // Re-read Keychain every time rather than trusting only the token that
        // happened to be loaded when this object was initialized.
        if appRemote.connectionParameters.accessToken?.isEmpty ?? true {
            _ = restoreTokenFromKeychain()
        }

        guard let token = appRemote.connectionParameters.accessToken,
              !token.isEmpty else {
            authorized = false
            authorizationRequired = true
            automaticRecoveryActive = false
            status = "Spotify authorization required"
            logger.log(
                "MEDIA AUTO",
                "No saved Spotify authorization; one-time authorization required"
            )
            return
        }

        authorized = true
        authorizationRequired = false
        automaticRecoveryActive = reconnectAttempt > 0 || consecutiveConnectionFailures > 0
        connectionInFlight = true

        status = automaticRecoveryActive
            ? "Recovering Spotify connection automatically…"
            : "Connecting to Spotify automatically…"

        logger.log(
            "MEDIA AUTO",
            "Connecting generation=\(remoteGeneration) attempt=\(reconnectAttempt + 1)"
        )
        appRemote.connect()
    }

    /// Automatic Spotify app-switch/wake is vehicle-gated. Silent App Remote
    /// connection attempts are still allowed anywhere, but `authorizeAndPlayURI`
    /// is never invoked automatically unless HUD or OBD evidence says the user is
    /// in the car. Manual Music/Reauthorize actions remain available at all times.
    func setAutomaticVehicleWakeAllowed(_ allowed: Bool, reason: String) {
        guard automaticVehicleWakeAllowed != allowed else { return }
        automaticVehicleWakeAllowed = allowed
        logger.log(
            "MEDIA WAKE",
            "Automatic Spotify wake vehicle gate = \(allowed) reason=\(reason)"
        )

        if allowed,
           !connected,
           authorized,
           !authorizationRequired,
           consecutiveConnectionFailures >= 2 {
            _ = attemptAutomaticSpotifyWake(reason: "vehicle session became eligible")
        }
    }

    func appBecameActive() {
        userRequestedDisconnect = false

        if automaticWakeInProgress {
            automaticWakeInProgress = false
            automaticWakeFallbackTask?.cancel()
            automaticWakeFallbackTask = nil
            logger.log("MEDIA WAKE", "HUD Controller became active after automatic Spotify wake; reconnecting")
        }

        guard !connected else {
            ensurePlayerStateSubscription()
            return
        }

        // This is the critical field-reliability behavior: if Spotify/HUD
        // Controller have been sitting for a long time, don't keep hammering a
        // potentially stale App Remote transport. Recreate it, restore the
        // Keychain token, then connect.
        rebuildAppRemote(reason: "app became active while disconnected")
        _ = restoreTokenFromKeychain()

        reconnectAttempt = 0
        consecutiveConnectionFailures = 0
        reconnectGeneration += 1
        autoConnectIfPossible()
    }

    func appEnteredBackground() {
        // We preserve the live connection if iOS permits it because HUD
        // Controller may still be executing for ScreenCaptureKit. If iOS or
        // Spotify drops App Remote, the next active transition always rebuilds
        // it from Keychain.
        logger.log(
            "MEDIA AUTO",
            "App backgrounded; preserving token and live App Remote when available"
        )
    }

    private func scheduleReconnect(reason: String) {
        guard !userRequestedDisconnect,
              !authorizationRequired,
              authorized else { return }
        guard reconnectTask == nil else { return }

        // A saved App Remote token is not enough to connect when the Spotify
        // process itself is suspended/terminated. After two ordinary connect
        // failures, automatically invoke Spotify's documented wake/authorization
        // path once. Existing Keychain authorization is preserved; this replaces
        // the former requirement for the user to tap Reauthorize almost every drive.
        if consecutiveConnectionFailures >= 2,
           attemptAutomaticSpotifyWake(reason: reason) {
            return
        }

        let delays: [Double] = [1, 2, 5, 10, 15]
        let delay = delays[min(reconnectAttempt, delays.count - 1)]
        reconnectAttempt += 1
        automaticRecoveryActive = true

        // After repeated -1000-style failures, throw away the transport object.
        // The Keychain authorization is preserved.
        if consecutiveConnectionFailures >= 2 {
            rebuildAppRemote(
                reason: "repeated connection failures (\(consecutiveConnectionFailures))"
            )
            _ = restoreTokenFromKeychain()
            consecutiveConnectionFailures = 0
        }

        reconnectGeneration += 1
        let generation = reconnectGeneration

        status = "Spotify reconnecting automatically…"
        logger.log(
            "MEDIA AUTO",
            "Scheduling reconnect generation=\(generation) in \(Int(delay))s reason=\(reason)"
        )

        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self,
                  !Task.isCancelled,
                  generation == self.reconnectGeneration,
                  !self.connected,
                  !self.userRequestedDisconnect,
                  !self.authorizationRequired else { return }

            self.reconnectTask = nil
            self.autoConnectIfPossible()
        }
    }

    @discardableResult
    private func attemptAutomaticSpotifyWake(reason: String) -> Bool {
        guard isConfigured, authorized, !authorizationRequired,
              !userRequestedDisconnect, !connected, !automaticWakeInProgress else {
            return false
        }

        guard automaticVehicleWakeAllowed else {
            logger.log(
                "MEDIA WAKE",
                "Automatic Spotify app wake suppressed outside vehicle session reason=\(reason)"
            )
            return false
        }

        let now = Date()
        if let lastAutomaticWakeAt,
           now.timeIntervalSince(lastAutomaticWakeAt) < automaticWakeCooldown {
            return false
        }

        automaticWakeInProgress = true
        lastAutomaticWakeAt = now
        automaticRecoveryActive = true
        connectionInFlight = false
        status = "Waking Spotify automatically…"
        _ = restoreTokenFromKeychain()

        logger.log(
            "MEDIA WAKE",
            "Automatic Spotify wake after connect failures; preserving Keychain authorization reason=\(reason)"
        )

        appRemote.authorizeAndPlayURI("") { installed in
            Task { @MainActor in
                self.logger.log("MEDIA WAKE", "Automatic Spotify wake installed=\(installed)")
                guard installed else {
                    self.automaticWakeInProgress = false
                    self.status = "Spotify app is not installed"
                    return
                }

                // Usually iOS switches to Spotify and then back through our callback.
                // Keep a bounded fallback in case Spotify wakes without delivering a
                // callback; a fresh App Remote is then connected with the saved token.
                self.automaticWakeFallbackTask?.cancel()
                self.automaticWakeFallbackTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(4))
                    guard let self, !Task.isCancelled, self.automaticWakeInProgress,
                          !self.connected else { return }
                    self.automaticWakeInProgress = false
                    self.automaticWakeFallbackTask = nil
                    self.rebuildAppRemote(reason: "automatic Spotify wake fallback")
                    _ = self.restoreTokenFromKeychain()
                    self.reconnectAttempt = 0
                    self.consecutiveConnectionFailures = 0
                    self.autoConnectIfPossible()
                }
            }
        }
        return true
    }

    private func ensurePlayerStateSubscription() {
        guard connected else { return }

        subscriptionRetryTask?.cancel()
        subscriptionRetryTask = nil

        appRemote.playerAPI?.delegate = self
        subscribeToPlayerState(attempt: 1)
    }

    private func subscribeToPlayerState(attempt: Int) {
        guard connected, attempt <= 4 else { return }

        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    self.logger.log(
                        "MEDIA ERROR",
                        "Player-state subscription attempt \(attempt): \(error.localizedDescription)"
                    )

                    guard attempt < 4, self.connected else { return }
                    self.subscriptionRetryTask?.cancel()
                    self.subscriptionRetryTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(1))
                        guard let self, !Task.isCancelled, self.connected else { return }
                        self.subscribeToPlayerState(attempt: attempt + 1)
                    }
                } else {
                    self.subscriptionRetryTask?.cancel()
                    self.subscriptionRetryTask = nil
                    self.logger.log(
                        "MEDIA",
                        "Subscribed to Spotify player state attempt=\(attempt)"
                    )
                }
            }
        })
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                if let error {
                    self.logger.log(
                        "MEDIA ERROR",
                        "Notification permission: \(error.localizedDescription)"
                    )
                } else {
                    self.logger.log("MEDIA", "Local notification permission = \(granted)")
                }
            }
        }
    }

    /// Normal/manual fallback. Existing authorization is always preserved.
    func connectOrAuthorize() {
        userRequestedDisconnect = false

        guard isConfigured else {
            status = "Spotify Client ID is not configured"
            logger.log("MEDIA ERROR", status)
            return
        }

        if SpotifyTokenStore.load() != nil {
            rebuildAppRemote(reason: "manual reconnect requested")
            _ = restoreTokenFromKeychain()
            reconnectAttempt = 0
            consecutiveConnectionFailures = 0
            reconnectGeneration += 1
            autoConnectIfPossible()
            return
        }

        beginAuthorization()
    }

    /// Wake/open Spotify without discarding the saved App Remote token.
    ///
    /// Spotify documents that plain `connect()` cannot wake the Spotify app
    /// when its process is not running. `authorizeAndPlayURI("")` performs the
    /// required app switch. If the user has already approved HUD Controller,
    /// Spotify can return/reuse authorization; we intentionally keep the
    /// existing Keychain token throughout this operation.
    func openSpotifyAndResumeConnection() {
        userRequestedDisconnect = false

        guard isConfigured else {
            status = "Spotify Client ID is not configured"
            return
        }

        // Preserve whatever authorization we already have.
        _ = restoreTokenFromKeychain()

        status = "Opening Spotify to resume connection…"
        logger.log(
            "MEDIA WAKE",
            "Opening Spotify via authorizeAndPlayURI without clearing Keychain authorization"
        )

        appRemote.authorizeAndPlayURI("") { installed in
            Task { @MainActor in
                self.logger.log("MEDIA WAKE", "Spotify installed = \(installed)")
                if !installed {
                    self.status = "Spotify app is not installed"
                }
            }
        }
    }

    /// Explicit troubleshooting action. This is the only normal UI action that
    /// intentionally discards the saved Spotify authorization.
    func reauthorize() {
        reconnectTask?.cancel()
        reconnectTask = nil
        subscriptionRetryTask?.cancel()
        subscriptionRetryTask = nil
        reconnectGeneration += 1
        reconnectAttempt = 0
        consecutiveConnectionFailures = 0
        automaticWakeInProgress = false
        automaticWakeFallbackTask?.cancel()
        automaticWakeFallbackTask = nil

        if appRemote.isConnected {
            appRemote.disconnect()
        }
        appRemote.connectionParameters.accessToken = nil
        SpotifyTokenStore.clear()

        connected = false
        authorized = false
        authorizationRequired = true
        connectionInFlight = false

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
        subscriptionRetryTask?.cancel()
        subscriptionRetryTask = nil
        reconnectGeneration += 1
        reconnectAttempt = 0
        consecutiveConnectionFailures = 0
        connectionInFlight = false
        automaticWakeInProgress = false
        automaticWakeFallbackTask?.cancel()
        automaticWakeFallbackTask = nil

        if appRemote.isConnected {
            appRemote.disconnect()
        }

        connected = false
        automaticRecoveryActive = false
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
            consecutiveConnectionFailures = 0
            automaticWakeInProgress = false
            automaticWakeFallbackTask?.cancel()
            automaticWakeFallbackTask = nil
            reconnectGeneration += 1
            connectionInFlight = false

            status = "Authorized; connecting…"
            logger.log(
                "MEDIA",
                "Spotify authorization callback received; token saved to Keychain"
            )
            autoConnectIfPossible()
            return true
        }

        if let error = parameters?[SPTAppRemoteErrorDescriptionKey] {
            connected = false
            authorized = false
            authorizationRequired = true
            connectionInFlight = false
            automaticRecoveryActive = false
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
                    self.logger.log(
                        "MEDIA ERROR",
                        "Local notification failed: \(error.localizedDescription)"
                    )
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
            // Ignore callbacks from an old generation that was intentionally
            // discarded during recovery.
            guard appRemote === self.appRemote else {
                self.logger.log("MEDIA AUTO", "Ignored connection callback from stale App Remote")
                return
            }

            self.reconnectTask?.cancel()
            self.reconnectTask = nil
            self.connectionInFlight = false
            self.userRequestedDisconnect = false
            self.reconnectAttempt = 0
            self.consecutiveConnectionFailures = 0
            self.automaticWakeInProgress = false
            self.automaticWakeFallbackTask?.cancel()
            self.automaticWakeFallbackTask = nil
            self.authorizationRequired = false
            self.authorized = true
            self.connected = true
            self.automaticRecoveryActive = false
            self.status = "Spotify connected"

            self.logger.log(
                "MEDIA",
                "Spotify App Remote connected generation=\(self.remoteGeneration)"
            )

            self.ensurePlayerStateSubscription()
        }
    }

    nonisolated func appRemote(
        _ appRemote: SPTAppRemote,
        didFailConnectionAttemptWithError error: Error?
    ) {
        Task { @MainActor in
            guard appRemote === self.appRemote else {
                self.logger.log("MEDIA AUTO", "Ignored failure callback from stale App Remote")
                return
            }

            self.connectionInFlight = false
            self.connected = false
            self.consecutiveConnectionFailures += 1
            self.status = "Spotify connection unavailable"

            let nsError = error as NSError?
            self.logger.log(
                "MEDIA ERROR",
                "Spotify connect failed generation=\(self.remoteGeneration) " +
                "domain=\(nsError?.domain ?? "nil") code=\(nsError?.code ?? -1) " +
                "description=\(error?.localizedDescription ?? "unknown")"
            )

            self.scheduleReconnect(
                reason: error?.localizedDescription ?? "connection attempt failed"
            )
        }
    }

    nonisolated func appRemote(
        _ appRemote: SPTAppRemote,
        didDisconnectWithError error: Error?
    ) {
        Task { @MainActor in
            guard appRemote === self.appRemote else {
                return
            }

            self.connectionInFlight = false
            self.connected = false
            self.status = "Spotify disconnected"

            self.logger.log(
                "MEDIA",
                "Spotify disconnected generation=\(self.remoteGeneration): " +
                "\(error?.localizedDescription ?? "no error")"
            )

            self.scheduleReconnect(
                reason: error?.localizedDescription ?? "unexpected disconnect"
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

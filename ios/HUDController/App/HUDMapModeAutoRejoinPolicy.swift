import Foundation

/// Pure scheduling policy for recovering a *missing* HUD MJPEG viewer.
/// The CarPlay H.264 decoder and iPhone -> adapter JPEG ingress are independent.
/// The caller must verify the current relay session before issuing any HUD
/// mode or Wi-Fi commands. HTTP timeout is unknown evidence, not a dead viewer.
enum HUDMapModeAutoRejoinPolicy {
    static let pollSeconds: TimeInterval = 6
    static let startupGraceSeconds: TimeInterval = 34
    static let cooldownSeconds: TimeInterval = 42
    static let maximumAttemptsPerBLESession = 3
    static let minimumFailedViewerChecks = 2

    static func shouldRetry(
        desiredModeEnabled: Bool,
        bleConnected: Bool,
        relayActive: Bool,
        sessionStatusAvailable: Bool,
        currentViewerReady: Bool,
        starterBusy: Bool,
        recoveryBusy: Bool,
        healthRecoveryExhausted: Bool,
        secondsSinceRelayStarted: TimeInterval,
        secondsSincePreviousRetry: TimeInterval,
        consecutiveMissingViewerChecks: Int,
        attemptedRetries: Int
    ) -> Bool {
        guard desiredModeEnabled, bleConnected, relayActive,
              sessionStatusAvailable, !currentViewerReady,
              !starterBusy, !recoveryBusy, !healthRecoveryExhausted,
              secondsSinceRelayStarted.isFinite,
              secondsSincePreviousRetry.isFinite else { return false }
        return secondsSinceRelayStarted >= startupGraceSeconds &&
            secondsSincePreviousRetry >= cooldownSeconds &&
            consecutiveMissingViewerChecks >= minimumFailedViewerChecks &&
            attemptedRetries < maximumAttemptsPerBLESession
    }
}

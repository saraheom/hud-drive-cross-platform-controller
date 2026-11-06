import Foundation

@main
struct ValidatePolicy {
    static func main() {
        func permitted(auto: Bool = true, ble: Bool = true, relay: Bool = true,
                       known: Bool = true, ready: Bool = false, starting: Bool = false,
                       recovering: Bool = false, exhausted: Bool = false,
                       elapsed: Double = 60, age: Double = 40,
                       misses: Int = 3, attempts: Int = 0) -> Bool {
            HUDMapModeAutoRejoinPolicy.shouldRetry(
                desiredModeEnabled: auto, bleConnected: ble, relayActive: relay,
                sessionStatusAvailable: known, currentViewerReady: ready,
                starterBusy: starting, recoveryBusy: recovering,
                healthRecoveryExhausted: exhausted,
                secondsSinceRelayStarted: age, secondsSincePreviousRetry: elapsed,
                consecutiveMissingViewerChecks: misses, attemptedRetries: attempts
            )
        }
        let cases: [(String, Bool, Bool)] = [
            ("known missing viewer qualifies", permitted(), true),
            ("healthy viewer untouched", permitted(ready: true), false),
            ("unavailable CGI does not trigger", permitted(known: false), false),
            ("startup grace", permitted(age: 14), false),
            ("consecutive failures", permitted(misses: 1), false),
            ("no BLE", permitted(ble: false), false),
            ("manual auto disable", permitted(auto: false), false),
            ("stop relay", permitted(relay: false), false),
            ("in progress startup", permitted(starting: true), false),
            ("in progress recovery", permitted(recovering: true), false),
            ("health budget exhausted", permitted(exhausted: true), false),
            ("cooldown", permitted(elapsed: 10), false),
            ("bounded attempts", permitted(attempts: 3), false),
            ("last permitted attempt", permitted(attempts: 2), true)
        ]
        for (name, actual, expected) in cases {
            precondition(actual == expected, "FAILED: \(name)")
        }
        print("PASS: \(cases.count) Linux/macOS Foundation policy checks")
    }
}

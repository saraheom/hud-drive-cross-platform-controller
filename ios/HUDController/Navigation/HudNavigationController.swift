import Foundation
import Observation

enum NavigationFeedOwner: String {
    case manual
    case ocr
    case carPlayAdapter
}

@MainActor
@Observable
final class HudNavigationController {
    var current = NavigationInstruction(
        maneuver: .right,
        distanceMeters: 46,
        primaryText: "Turn right",
        streetName: "Main St"
    )
    private(set) var simulatorRunning = false
    private(set) var navigationActive = false
    private(set) var feedOwner: NavigationFeedOwner = .manual
    private var simulatorTask: Task<Void, Never>?

    let bluetooth: HudBluetoothManager
    let logger: LogManager

    init(bluetooth: HudBluetoothManager, logger: LogManager) {
        self.bluetooth = bluetooth
        self.logger = logger
    }

    private func canTakeOwnership(_ owner: NavigationFeedOwner) -> Bool {
        if feedOwner == .carPlayAdapter && owner != .carPlayAdapter { return false }
        return true
    }

    func navigationOn(owner: NavigationFeedOwner = .manual) {
        guard canTakeOwnership(owner) else {
            logger.log("NAV SOURCE", "Ignored Navigation ON from \(owner.rawValue); live CarPlay adapter owns HUD")
            return
        }
        let changed = !navigationActive || feedOwner != owner
        feedOwner = owner
        navigationActive = true
        if changed {
            bluetooth.enqueue(HudCommands.navigationState(true), label: "Navigation ON (\(owner.rawValue))")
            logger.log("DASHBOARD MODE", "Navigation active owner=\(owner.rawValue)")
        }
    }

    func navigationOff(owner: NavigationFeedOwner = .manual) {
        // A stale OCR frame or capture-health watchdog must never knock the HUD
        // out of live CarPlay navigation.  The adapter releases its own lease
        // when no fresh RGD source remains.
        if feedOwner == .carPlayAdapter && owner != .carPlayAdapter {
            logger.log("NAV SOURCE", "Ignored Navigation OFF from \(owner.rawValue); live CarPlay adapter owns HUD")
            return
        }
        if owner != .manual && feedOwner != owner { return }
        stopSimulator()
        guard navigationActive else { return }
        navigationActive = false
        feedOwner = .manual
        bluetooth.enqueue(HudCommands.navigationState(false), label: "Navigation OFF (\(owner.rawValue))")
        logger.log("DASHBOARD MODE", "Navigation inactive; HUD Freeride mode active")
    }

    func sendCurrent(owner: NavigationFeedOwner = .manual) {
        guard canTakeOwnership(owner) else {
            logger.log("NAV SOURCE", "Suppressed maneuver from \(owner.rawValue); live CarPlay adapter owns HUD")
            return
        }
        feedOwner = owner
        logger.log("NAV", "owner=\(owner.rawValue) \(current.maneuver.label), \(current.distanceMeters)m, \(current.streetName)")
        // The stock Android app applies DisplaySpeedUintsCommandPacket as part
        // of HUD settings. Reassert it here so a physical HUD reboot cannot
        // format a correct meter distance using a stale/default unit mode.
        bluetooth.enqueue(HudCommands.imperialUnits(), label: "Navigation → imperial units")
        bluetooth.enqueue(HudCommands.maneuver(current), label: "Maneuver (\(owner.rawValue))")
    }

    func sendETA(arrivalTimeMilliseconds: Int64, owner: NavigationFeedOwner = .manual) {
        guard canTakeOwnership(owner) else { return }
        guard arrivalTimeMilliseconds > 0 else { return }
        feedOwner = owner
        bluetooth.enqueue(
            HudCommands.eta(arrivalTimeMilliseconds: arrivalTimeMilliseconds),
            label: "ETA \(Date(timeIntervalSince1970: TimeInterval(arrivalTimeMilliseconds) / 1000.0).formatted(date: .omitted, time: .shortened))"
        )
        logger.log("NAV ETA", "owner=\(owner.rawValue) arrivalMs=\(arrivalTimeMilliseconds)")
    }

    func startSimulator() {
        guard !simulatorRunning else { return }
        simulatorRunning = true
        simulatorTask = Task { @MainActor in
            navigationOn()
            let legs: [(HudManeuver, String, String, Int)] = [
                (.straight, "Continue straight", "Oak Avenue", 120),
                (.right, "Turn right", "Main St", 100),
                (.keepLeft, "Keep left", "US-1 North", 140),
                (.exitRight, "Take exit 12B", "Market Street", 120),
                (.left, "Turn left", "Destination Drive", 80),
            ]
            for (maneuver, primary, street, start) in legs {
                if Task.isCancelled { break }
                for ratio in [1.0, 0.8, 0.6, 0.4, 0.2] {
                    if Task.isCancelled { break }
                    current = .init(
                        maneuver: maneuver,
                        distanceMeters: max(5, Int(Double(start) * ratio)),
                        primaryText: primary,
                        streetName: street
                    )
                    sendCurrent()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            if !Task.isCancelled {
                current = .init(maneuver: .destination, distanceMeters: 0,
                                primaryText: "You have arrived", streetName: "Destination Drive")
                sendCurrent()
            }
            simulatorRunning = false
        }
    }

    func stopSimulator() {
        simulatorTask?.cancel()
        simulatorTask = nil
        simulatorRunning = false
        logger.log("NAV", "Simulator stopped")
    }
}

import Foundation
import Observation

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
    private var simulatorTask: Task<Void, Never>?

    let bluetooth: HudBluetoothManager
    let logger: LogManager

    init(bluetooth: HudBluetoothManager, logger: LogManager) {
        self.bluetooth = bluetooth
        self.logger = logger
    }

    func navigationOn() {
        navigationActive = true
        bluetooth.enqueue(HudCommands.navigationState(true), label: "Navigation ON")
        logger.log("DASHBOARD MODE", "Navigation active")
    }

    func navigationOff() {
        stopSimulator()
        navigationActive = false
        bluetooth.enqueue(HudCommands.navigationState(false), label: "Navigation OFF")
        logger.log("DASHBOARD MODE", "Navigation inactive; HUD Freeride mode active")
    }

    func sendCurrent() {
        logger.log("NAV", "\(current.maneuver.label), \(current.distanceMeters)m, \(current.streetName)")
        // The stock Android app applies DisplaySpeedUintsCommandPacket as part
        // of HUD settings. Reassert it here too so a physical HUD reboot cannot
        // format a correct meter distance using a stale/default unit mode.
        bluetooth.enqueue(HudCommands.imperialUnits(), label: "Navigation → imperial units")
        bluetooth.enqueue(HudCommands.maneuver(current), label: "Maneuver")
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

import Foundation
import Observation

@MainActor
@Observable
final class HudwayNavigationController {
    var current = NavigationInstruction(
        maneuver: .right,
        distanceMeters: 46,
        primaryText: "Turn right",
        streetName: "Main St"
    )
    private(set) var simulatorRunning = false
    private var simulatorTask: Task<Void, Never>?

    let bluetooth: HudwayBluetoothManager
    let logger: LogManager

    init(bluetooth: HudwayBluetoothManager, logger: LogManager) {
        self.bluetooth = bluetooth
        self.logger = logger
    }

    func navigationOn() {
        bluetooth.enqueue(HudwayCommands.navigationState(true), label: "Navigation ON")
    }

    func navigationOff() {
        stopSimulator()
        bluetooth.enqueue(HudwayCommands.navigationState(false), label: "Navigation OFF")
    }

    func sendCurrent() {
        logger.log("NAV", "\(current.maneuver.label), \(current.distanceMeters)m, \(current.streetName)")
        bluetooth.enqueue(HudwayCommands.maneuver(current), label: "Maneuver")
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

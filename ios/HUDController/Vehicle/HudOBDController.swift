import Foundation
import Observation

enum HudOBDItem: Int, CaseIterable, Identifiable {
    case none = 0
    case remainingDistance = 1
    case averageFuel = 2
    case remainingFuel = 3
    case batteryVoltage = 4
    case coolantTemperature = 5
    case gear = 6
    case fuelInjectionRate = 7
    case dpfStatus = 8
    case dpfStoredData = 9
    case drivingVelocity = 10
    case rpmLevels = 11
    case averageFuelConsumption = 12
    case obdState = 13

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .remainingDistance: return "Remaining distance"
        case .averageFuel: return "Average fuel"
        case .remainingFuel: return "Remaining fuel"
        case .batteryVoltage: return "Battery voltage"
        case .coolantTemperature: return "Coolant temperature"
        case .gear: return "Gear"
        case .fuelInjectionRate: return "Fuel injection rate"
        case .dpfStatus: return "DPF status"
        case .dpfStoredData: return "DPF stored data"
        case .drivingVelocity: return "Driving velocity"
        case .rpmLevels: return "RPM levels"
        case .averageFuelConsumption: return "Average fuel consumption"
        case .obdState: return "OBD state"
        }
    }
}

@MainActor
@Observable
final class HudOBDController {
    private let bluetooth: HudBluetoothManager
    private let logger: LogManager

    var deviceName = UserDefaults.standard.string(forKey: "HUD.OBD.deviceName") ?? "OBDII"
    var autoConnect = UserDefaults.standard.object(forKey: "HUD.OBD.autoConnect") as? Bool ?? true

    private(set) var connected = false
    private(set) var supportedPIDs = ""
    private(set) var status = "Not connected"

    var leftItem: HudOBDItem = .coolantTemperature
    var rightItem: HudOBDItem = .rpmLevels

    init(bluetooth: HudBluetoothManager, logger: LogManager) {
        self.bluetooth = bluetooth
        self.logger = logger
        bluetooth.onOBDConnectionEvent = { [weak self] connected, pids in
            guard let self else { return }
            self.connected = connected
            self.supportedPIDs = pids
            self.status = connected ? "Connected through HUD" : "Disconnected"
            self.logger.log("OBD EVENT", "connected=\(connected), supported=\(pids)")
            if connected {
                self.applyWidgetSelection()
            }
        }
    }

    func connect() {
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "OBDII" : deviceName
        deviceName = name
        UserDefaults.standard.set(name, forKey: "HUD.OBD.deviceName")
        UserDefaults.standard.set(autoConnect, forKey: "HUD.OBD.autoConnect")
        status = "HUD is searching for \(name)…"
        logger.log("OBD", "Request HUD-side OBD connection to \(name)")
        bluetooth.enqueue(
            HudCommands.obdConnection(enabled: true, deviceName: name),
            label: "OBD connect \(name)"
        )
    }

    func disconnect() {
        status = "Disconnect requested"
        bluetooth.enqueue(
            HudCommands.obdConnection(enabled: false, deviceName: deviceName),
            label: "OBD disconnect"
        )
    }

    func applyWidgetSelection() {
        // Original packet has only integer position/index. JADX does not expose
        // named position constants, so v24 uses the natural 0=left, 1=right
        // hypothesis and logs the exact packets for physical verification.
        bluetooth.enqueue(
            HudCommands.obdCustomItem(position: 0, itemIndex: Int32(leftItem.rawValue)),
            label: "OBD left widget \(leftItem.displayName)"
        )
        bluetooth.enqueue(
            HudCommands.obdCustomItem(position: 1, itemIndex: Int32(rightItem.rawValue)),
            label: "OBD right widget \(rightItem.displayName)"
        )
        logger.log(
            "OBD WIDGETS",
            "left(pos0)=\(leftItem.displayName), right(pos1)=\(rightItem.displayName)"
        )
    }

    func hudDidBecomeReady() {
        if autoConnect {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.connect()
            }
        }
    }
}

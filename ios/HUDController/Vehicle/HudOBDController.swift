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

    var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: "HUD.OBD.deviceName") }
    }
    var autoConnect: Bool {
        didSet { UserDefaults.standard.set(autoConnect, forKey: "HUD.OBD.autoConnect") }
    }

    private(set) var connected = false
    private(set) var supportedPIDs = ""
    private(set) var status = "Not connected"

    var freerideLeft: HudOBDItem { didSet { saveItem(freerideLeft, key: "HUD.OBD.freerideLeft") } }
    var freerideRight: HudOBDItem { didSet { saveItem(freerideRight, key: "HUD.OBD.freerideRight") } }
    var navigationLeft: HudOBDItem { didSet { saveItem(navigationLeft, key: "HUD.OBD.navigationLeft") } }
    var navigationRight: HudOBDItem { didSet { saveItem(navigationRight, key: "HUD.OBD.navigationRight") } }

    init(bluetooth: HudBluetoothManager, logger: LogManager) {
        self.bluetooth = bluetooth
        self.logger = logger
        let d = UserDefaults.standard
        self.deviceName = d.string(forKey: "HUD.OBD.deviceName") ?? "OBDII"
        self.autoConnect = d.object(forKey: "HUD.OBD.autoConnect") == nil ? true : d.bool(forKey: "HUD.OBD.autoConnect")
        self.freerideLeft = Self.loadItem("HUD.OBD.freerideLeft", fallback: .coolantTemperature)
        self.freerideRight = Self.loadItem("HUD.OBD.freerideRight", fallback: .rpmLevels)
        self.navigationLeft = Self.loadItem("HUD.OBD.navigationLeft", fallback: .drivingVelocity)
        self.navigationRight = Self.loadItem("HUD.OBD.navigationRight", fallback: .remainingDistance)

        bluetooth.onOBDConnectionEvent = { [weak self] connected, pids in
            guard let self else { return }
            self.connected = connected
            self.supportedPIDs = pids
            self.status = connected ? "Connected through HUD" : "Disconnected"
            self.logger.log("OBD EVENT", "connected=\(connected), supported=\(pids)")
        }
    }

    private static func loadItem(_ key: String, fallback: HudOBDItem) -> HudOBDItem {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return HudOBDItem(rawValue: UserDefaults.standard.integer(forKey: key)) ?? fallback
    }

    private func saveItem(_ item: HudOBDItem, key: String) {
        UserDefaults.standard.set(item.rawValue, forKey: key)
    }

    func connect() {
        if connected {
            status = "Connected through HUD"
            logger.log("OBD", "Connect request ignored: already connected")
            return
        }
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
        applyFreerideWidgets()
        applyNavigationWidgets()
    }

    func applyFreerideWidgets() {
        sendWidget(position: 0, item: freerideLeft, label: "Freeride left")
        sendWidget(position: 1, item: freerideRight, label: "Freeride right")
    }

    func applyNavigationWidgets() {
        // Decompiled UI exposes independent navigation left/right slots.
        // v30 tests positions 2/3 for that second profile; logs make this
        // easy to revise if the firmware uses another position mapping.
        sendWidget(position: 2, item: navigationLeft, label: "Navigation left")
        sendWidget(position: 3, item: navigationRight, label: "Navigation right")
    }

    private func sendWidget(position: Int32, item: HudOBDItem, label: String) {
        bluetooth.enqueue(
            HudCommands.obdCustomItem(position: position, itemIndex: Int32(item.rawValue)),
            label: "OBD \(label) widget \(item.displayName)"
        )
        logger.log("OBD WIDGETS", "\(label)(pos\(position))=\(item.displayName)")
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

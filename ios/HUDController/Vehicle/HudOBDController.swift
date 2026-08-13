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
    private var autoConnectTask: Task<Void, Never>?
    private var autoConnectAttempt = 0

    var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: "HUD.OBD.deviceName") }
    }
    var autoConnect: Bool {
        didSet {
            UserDefaults.standard.set(autoConnect, forKey: "HUD.OBD.autoConnect")
            if autoConnect {
                startAutoConnectLoop(reason: "Auto-connect enabled")
            } else {
                autoConnectTask?.cancel()
                autoConnectTask = nil
                autoConnectAttempt = 0
            }
        }
    }

    private(set) var connected = false
    private(set) var supportedPIDs = ""
    private(set) var status = "Not connected"

    var freerideLeft: HudSideWidget { didSet { saveWidget(freerideLeft, key: "HUD.Widget.freerideLeft") } }
    var freerideRight: HudSideWidget { didSet { saveWidget(freerideRight, key: "HUD.Widget.freerideRight") } }
    var navigationLeft: HudSideWidget { didSet { saveWidget(navigationLeft, key: "HUD.Widget.navigationLeft") } }
    var navigationRight: HudSideWidget { didSet { saveWidget(navigationRight, key: "HUD.Widget.navigationRight") } }


    init(bluetooth: HudBluetoothManager, logger: LogManager) {
        self.bluetooth = bluetooth
        self.logger = logger
        let d = UserDefaults.standard
        self.deviceName = d.string(forKey: "HUD.OBD.deviceName") ?? "OBDII"

        // v45 migration: previous troubleshooting often left this persisted
        // OFF. The new design is explicitly self-healing, so migrate existing
        // installs to auto-connect ON once. A user turning it OFF after this
        // migration remains respected.
        if !d.bool(forKey: "HUD.OBD.v45AutoConnectMigrated") {
            d.set(true, forKey: "HUD.OBD.autoConnect")
            d.set(true, forKey: "HUD.OBD.v45AutoConnectMigrated")
        }
        self.autoConnect = d.object(forKey: "HUD.OBD.autoConnect") == nil
            ? true
            : d.bool(forKey: "HUD.OBD.autoConnect")
        self.freerideLeft = Self.loadWidget("HUD.Widget.freerideLeft", fallback: .distance)
        self.freerideRight = Self.loadWidget("HUD.Widget.freerideRight", fallback: .tripTime)
        self.navigationLeft = Self.loadWidget("HUD.Widget.navigationLeft", fallback: .speed)
        self.navigationRight = Self.loadWidget("HUD.Widget.navigationRight", fallback: .time)

        bluetooth.onOBDConnectionEvent = { [weak self] connected, pids in
            guard let self else { return }
            self.connected = connected
            self.supportedPIDs = pids
            self.status = connected ? "Connected through HUD" : "Disconnected"
            if connected {
                self.autoConnectTask?.cancel()
                self.autoConnectTask = nil
                self.autoConnectAttempt = 0
            } else if self.autoConnect {
                self.startAutoConnectLoop(reason: "HUD reported OBD disconnected")
            }
            self.logger.log("OBD EVENT", "connected=\(connected), supported=\(pids)")
        }
    }

    private static func loadWidget(_ key: String, fallback: HudSideWidget) -> HudSideWidget {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return fallback }
        return HudSideWidget(rawValue: raw) ?? fallback
    }

    private func saveWidget(_ widget: HudSideWidget, key: String) {
        UserDefaults.standard.set(widget.rawValue, forKey: key)
    }

    func connect(force: Bool = false) {
        if connected && !force {
            status = "Connected through HUD"
            logger.log("OBD", "Connect request ignored: already connected")
            return
        }

        if force && connected {
            logger.log("OBD", "Forced connect requested; clearing stale connected state")
            connected = false
            supportedPIDs = ""
        }

        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "OBDII" : deviceName
        deviceName = name
        status = "HUD is searching for \(name)…"
        logger.log("OBD", "Request HUD-side OBD connection to \(name)")
        bluetooth.enqueue(
            HudCommands.obdConnection(enabled: true, deviceName: name),
            label: "OBD connect \(name)"
        )
    }


    func disconnect() {
        autoConnectTask?.cancel()
        autoConnectTask = nil
        autoConnectAttempt = 0
        connected = false
        supportedPIDs = ""
        status = "Disconnect requested"
        bluetooth.enqueue(
            HudCommands.obdConnection(enabled: false, deviceName: deviceName),
            label: "OBD disconnect"
        )
        logger.log("OBD", "Local OBD state cleared immediately after disconnect request")
    }


    func applyWidgetSelection() {
        applyFreerideWidgets()
        applyNavigationWidgets()
    }

    func applyFreerideWidgets() {
        // Original app: HudWidgetCommandPacket type=0 for Freeride.
        bluetooth.enqueue(
            HudCommands.dashboard(
                left: freerideLeft.rawValue,
                center: "Simple",
                right: freerideRight.rawValue,
                navigationLayout: false
            ),
            label: "Freeride dashboard \(freerideLeft.displayName) | Simple | \(freerideRight.displayName)"
        )
        logger.log(
            "DASHBOARD",
            "Freeride type=0 left=\(freerideLeft.rawValue) center=Simple right=\(freerideRight.rawValue)"
        )
    }

    func applyNavigationWidgets() {
        // Original app: HudWidgetCommandPacket type=1 for Navigation.
        bluetooth.enqueue(
            HudCommands.dashboard(
                left: navigationLeft.rawValue,
                center: "Navigation",
                right: navigationRight.rawValue,
                navigationLayout: true
            ),
            label: "Navigation dashboard \(navigationLeft.displayName) | Navigation | \(navigationRight.displayName)"
        )
        logger.log(
            "DASHBOARD",
            "Navigation type=1 left=\(navigationLeft.rawValue) center=Navigation right=\(navigationRight.rawValue)"
        )
    }

    func hudDidBecomeReady() {
        hudSessionDidReset(reason: "HUD transport became ready")
        applyWidgetSelection()
    }

    func hudSessionDidReset(reason: String) {
        autoConnectTask?.cancel()
        autoConnectTask = nil
        autoConnectAttempt = 0
        connected = false
        supportedPIDs = ""
        status = autoConnect ? "HUD reset detected; reconnecting OBD…" : "HUD reset detected"
        logger.log("OBD SESSION", "\(reason); cleared stale OBD connection state")

        if autoConnect {
            startAutoConnectLoop(reason: reason)
        }
    }

    func transportDisconnected() {
        autoConnectTask?.cancel()
        autoConnectTask = nil
        autoConnectAttempt = 0
        connected = false
        supportedPIDs = ""
        status = "HUD disconnected"
        logger.log("OBD SESSION", "HUD BLE transport disconnected; cleared OBD state")
    }

    private func startAutoConnectLoop(reason: String) {
        guard autoConnect else { return }
        guard autoConnectTask == nil else { return }

        logger.log("OBD AUTO", "Starting retry loop: \(reason)")
        autoConnectTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Give the HUD firmware a moment to finish its own startup.
            try? await Task.sleep(for: .seconds(2))

            while !Task.isCancelled && self.autoConnect && !self.connected {
                guard self.bluetooth.state == .connected else {
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }

                self.autoConnectAttempt += 1
                self.logger.log("OBD AUTO", "Connect attempt \(self.autoConnectAttempt)")
                self.connect(force: true)

                // The physical HUD can take several seconds to connect to ELM327.
                // Retry until its OBD event explicitly reports connected=true.
                try? await Task.sleep(for: .seconds(4))
            }

            if self.connected {
                self.logger.log("OBD AUTO", "Retry loop completed: OBD connected")
            }
            self.autoConnectTask = nil
        }
    }

}
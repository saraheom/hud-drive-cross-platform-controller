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
    private var healthTask: Task<Void, Never>?
    private var autoConnectAttempt = 0
    private var autoConnectGeneration = 0
    private var lastPositiveConnectionEvent = Date.distantPast

    var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: "HUD.OBD.deviceName") }
    }
    var autoConnect: Bool {
        didSet {
            UserDefaults.standard.set(autoConnect, forKey: "HUD.OBD.autoConnect")
            if autoConnect {
                startAutoConnectLoop(reason: "Auto-connect enabled")
                startHealthLoop()
            } else {
                autoConnectGeneration += 1
                autoConnectTask?.cancel()
                autoConnectTask = nil
                healthTask?.cancel()
                healthTask = nil
                autoConnectAttempt = 0
            }
        }
    }

    private(set) var connected = false
    private(set) var supportedPIDs = ""
    private(set) var status = "Not connected"
    var onConnectionChanged: ((Bool) -> Void)?

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
        // v90.31 default Navigation layout: Speed | Navigation | ETA. Migrate
        // only the legacy default-looking Speed + Time pair; any other explicit
        // widget customization remains untouched.
        if !d.bool(forKey: "HUD.Widget.v9031NavigationEtaMigrated") {
            let oldLeft = d.string(forKey: "HUD.Widget.navigationLeft")
            let oldRight = d.string(forKey: "HUD.Widget.navigationRight")
            let legacyDefaultPair = (oldLeft == nil || oldLeft == HudSideWidget.speed.rawValue)
                && (oldRight == nil || oldRight == HudSideWidget.time.rawValue)
            if legacyDefaultPair {
                d.set(HudSideWidget.speed.rawValue, forKey: "HUD.Widget.navigationLeft")
                d.set(HudSideWidget.eta.rawValue, forKey: "HUD.Widget.navigationRight")
            }
            d.set(true, forKey: "HUD.Widget.v9031NavigationEtaMigrated")
        }

        self.freerideLeft = Self.loadWidget("HUD.Widget.freerideLeft", fallback: .distance)
        self.freerideRight = Self.loadWidget("HUD.Widget.freerideRight", fallback: .tripTime)
        self.navigationLeft = Self.loadWidget("HUD.Widget.navigationLeft", fallback: .speed)
        self.navigationRight = Self.loadWidget("HUD.Widget.navigationRight", fallback: .eta)

        bluetooth.onOBDConnectionEvent = { [weak self] connected, pids in
            guard let self else { return }
            self.connected = connected
            self.supportedPIDs = pids
            self.status = connected ? "Connected through HUD" : "Disconnected"
            if connected {
                self.lastPositiveConnectionEvent = Date()
                self.autoConnectTask?.cancel()
                self.autoConnectTask = nil
                self.autoConnectAttempt = 0
                self.startHealthLoop()
            } else if self.autoConnect {
                self.startAutoConnectLoop(reason: "HUD reported OBD disconnected")
            }
            self.onConnectionChanged?(connected)
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
        autoConnectGeneration += 1
        autoConnectTask?.cancel()
        autoConnectTask = nil
        healthTask?.cancel()
        healthTask = nil
        autoConnectAttempt = 0
        connected = false
        supportedPIDs = ""
        status = "Disconnect requested"
        onConnectionChanged?(false)
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
        autoConnectGeneration += 1
        autoConnectTask?.cancel()
        autoConnectTask = nil
        autoConnectAttempt = 0
        connected = false
        supportedPIDs = ""
        status = autoConnect ? "HUD reset detected; reconnecting OBD…" : "HUD reset detected"
        onConnectionChanged?(false)
        logger.log("OBD SESSION", "\(reason); cleared stale OBD connection state")

        if autoConnect {
            startAutoConnectLoop(reason: reason)
            startHealthLoop()
        }
    }

    func transportDisconnected() {
        autoConnectGeneration += 1
        autoConnectTask?.cancel()
        autoConnectTask = nil
        healthTask?.cancel()
        healthTask = nil
        autoConnectAttempt = 0
        connected = false
        supportedPIDs = ""
        status = "HUD disconnected — physical OBD power unknown"
        // v90.15 engine consensus is explicitly based on the app-visible HUD and
        // OBD2 connection states. Losing HUD transport necessarily makes the
        // through-HUD OBD connection unavailable too, so publish that state. The
        // AmbientLightMonitor still has an independent direct-OBD BLE witness that
        // can veto a false engine-OFF decision during a HUD-only reboot.
        onConnectionChanged?(false)
        logger.log("OBD SESSION", "HUD BLE transport disconnected; published OBD connection=false while physical OBD power remains independently witnessable")
    }

    private func startAutoConnectLoop(reason: String) {
        guard autoConnect else { return }
        guard autoConnectTask == nil else { return }

        autoConnectGeneration += 1
        let generation = autoConnectGeneration
        logger.log("OBD AUTO", "Starting retry loop generation=\(generation): \(reason)")
        autoConnectTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Give the HUD firmware a moment to finish its own startup.
            try? await Task.sleep(for: .seconds(2))

            while !Task.isCancelled &&
                    generation == self.autoConnectGeneration &&
                    self.autoConnect && !self.connected {
                guard self.bluetooth.state == .connected else {
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }

                self.autoConnectAttempt += 1
                self.logger.log("OBD AUTO", "Connect attempt \(self.autoConnectAttempt)")
                self.connect(force: true)

                // v90.16: field logs showed some HUD firmware sessions never emit
                // OBDConnectionEventPacket connected=true even while the vehicle
                // and HUD remain fully operational. Do not hammer the HUD every
                // four seconds indefinitely. Keep retrying, but back off to a
                // 30-second ceiling so OBD recovery remains self-healing without
                // adding hundreds of redundant UART commands during one drive.
                let retryDelay: Double
                switch self.autoConnectAttempt {
                case 1: retryDelay = 4.0
                case 2: retryDelay = 6.0
                case 3: retryDelay = 9.0
                case 4: retryDelay = 14.0
                case 5: retryDelay = 20.0
                default: retryDelay = 30.0
                }
                self.logger.log(
                    "OBD AUTO",
                    "No positive OBD connection event yet; next retry in \(String(format: "%.1f", retryDelay))s"
                )
                try? await Task.sleep(for: .seconds(retryDelay))
            }

            if self.connected {
                self.logger.log("OBD AUTO", "Retry loop completed: OBD connected")
            }
            if generation == self.autoConnectGeneration {
                self.autoConnectTask = nil
            }
        }
    }


    private func startHealthLoop() {
        guard autoConnect, healthTask == nil else { return }

        healthTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled && self.autoConnect {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }

                guard self.bluetooth.state == .connected else {
                    self.connected = false
                    self.status = "HUD unavailable; OBD reconnect pending"
                    continue
                }

                if !self.connected {
                    self.startAutoConnectLoop(reason: "OBD health watchdog found disconnected state")
                    continue
                }

                // The decompiled HUD protocol exposes connection state and
                // supported-PID masks, but not a stream of raw OBD PID values
                // back to the phone. Therefore we cannot truthfully use RPM or
                // speed-value freshness as a phone-side heartbeat. Instead,
                // periodically reassert the idempotent HUD-side connect
                // command. This recovers a silently lost ELM link without
                // requiring the user to toggle Disconnect/Connect.
                let name = self.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "OBDII" : self.deviceName
                self.bluetooth.enqueue(
                    HudCommands.obdConnection(enabled: true, deviceName: name),
                    label: "OBD health keep-connected \(name)"
                )
                self.logger.log(
                    "OBD HEALTH",
                    "Reasserted HUD→OBD connection; supportedPIDs=\(self.supportedPIDs.isEmpty ? "none" : self.supportedPIDs)"
                )
            }

            self.healthTask = nil
        }
    }


}
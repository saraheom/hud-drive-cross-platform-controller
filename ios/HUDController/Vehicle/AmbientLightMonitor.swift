import Foundation
import CoreBluetooth
import Observation

@MainActor
@Observable
final class AmbientLightMonitor: NSObject, CBCentralManagerDelegate {
    private(set) var status = "Stopped"
    private(set) var detectedName = "BLEDOM"
    private(set) var detectedIdentifier = ""
    private(set) var lastRSSI: Int?
    private(set) var lightPresent = false

    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "HUD.Ambient.enabled")
            enabled ? start() : stop()
        }
    }
    var targetName: String {
        didSet { UserDefaults.standard.set(targetName, forKey: "HUD.Ambient.targetName") }
    }
    var absenceTimeoutSeconds: Int {
        didSet { UserDefaults.standard.set(absenceTimeoutSeconds, forKey: "HUD.Ambient.timeout") }
    }

    private var central: CBCentralManager!
    private let bluetooth: HudBluetoothManager
    private let logger: LogManager
    private var lastSeen = Date.distantPast
    private var watchdogTask: Task<Void, Never>?

    init(bluetooth: HudBluetoothManager, logger: LogManager) {
        self.bluetooth = bluetooth
        self.logger = logger
        let d = UserDefaults.standard
        self.enabled = d.object(forKey: "HUD.Ambient.enabled") == nil ? false : d.bool(forKey: "HUD.Ambient.enabled")
        self.targetName = d.string(forKey: "HUD.Ambient.targetName") ?? "BLEDOM"
        self.absenceTimeoutSeconds = d.object(forKey: "HUD.Ambient.timeout") == nil ? 5 : max(1, d.integer(forKey: "HUD.Ambient.timeout"))
        super.init()

        // Restoration is now implemented rather than disabled. Combined with
        // UIBackgroundModes bluetooth-central this gives iOS the best chance
        // to relaunch/continue the BLE central while backgrounded.
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "HUDAmbientCentral"]
        )
    }

    func start() {
        guard central.state == .poweredOn else {
            status = "Waiting for Bluetooth"
            return
        }
        status = "Scanning for \(targetName)…"
        logger.log("AMBIENT", "Scanning app-level BLE advertisements for \(targetName)")
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        startWatchdog()
    }

    func stop() {
        central.stopScan()
        watchdogTask?.cancel()
        watchdogTask = nil
        status = "Stopped"
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        Task { @MainActor in
            self.logger.log("AMBIENT BG", "CoreBluetooth restored ambient central state")
            if self.enabled && central.state == .poweredOn {
                self.start()
            }
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.logger.log("AMBIENT", "Central state \(central.state.rawValue)")
            if self.enabled && central.state == .poweredOn {
                self.start()
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let name = peripheral.name ?? localName ?? ""
            guard name.localizedCaseInsensitiveContains(self.targetName) else { return }

            self.lastSeen = Date()
            self.detectedName = name
            self.detectedIdentifier = peripheral.identifier.uuidString
            self.lastRSSI = RSSI.intValue
            self.status = "\(name) present • RSSI \(RSSI.intValue)"

            if !self.lightPresent {
                self.lightPresent = true
                self.logger.log("AMBIENT", "\(name) became present; enabling HUD auto brightness")
                if self.bluetooth.state == .connected {
                    self.bluetooth.enqueue(HudCommands.autoBrightness(true), label: "Ambient trigger → Auto brightness ON")
                }
            }
        }
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard self.enabled else { continue }
                if self.lightPresent &&
                    Date().timeIntervalSince(self.lastSeen) > Double(self.absenceTimeoutSeconds) {
                    self.lightPresent = false
                    self.status = "\(self.targetName) absent"
                    self.logger.log("AMBIENT", "\(self.targetName) absent for \(self.absenceTimeoutSeconds)s; disabling HUD auto brightness")
                    if self.bluetooth.state == .connected {
                        self.bluetooth.enqueue(HudCommands.autoBrightness(false), label: "Ambient trigger → Auto brightness OFF")
                    }
                }
            }
        }
    }
}

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
        didSet {
            // Never assign to an observed property from its own didSet. That
            // re-entered Observation/SwiftUI during Stepper changes and could
            // crash the app. The UI supplies an already-clamped value.
            UserDefaults.standard.set(Self.clampedTimeout(absenceTimeoutSeconds), forKey: "HUD.Ambient.timeout")
        }
    }

    static func clampedTimeout(_ value: Int) -> Int { max(1, min(30, value)) }

    func setAbsenceTimeout(_ value: Int) {
        absenceTimeoutSeconds = Self.clampedTimeout(value)
    }

    private var central: CBCentralManager!
    private let bluetooth: HudBluetoothManager
    private let logger: LogManager

    private var trackedPeripheral: CBPeripheral?
    private var lastSeen = Date.distantPast
    private var watchdogTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var connectionAttemptStartedAt: Date?
    private var lastHUDReassertAt = Date.distantPast
    private let absenceConfirmationWindows = 3

    private let peripheralIDKey = "HUD.Ambient.peripheralUUID"

    init(bluetooth: HudBluetoothManager, logger: LogManager) {
        self.bluetooth = bluetooth
        self.logger = logger

        let d = UserDefaults.standard
        self.enabled = d.object(forKey: "HUD.Ambient.enabled") == nil
            ? false : d.bool(forKey: "HUD.Ambient.enabled")
        self.targetName = d.string(forKey: "HUD.Ambient.targetName") ?? "BLEDOM"
        self.absenceTimeoutSeconds = d.object(forKey: "HUD.Ambient.timeout") == nil
            ? 5 : Self.clampedTimeout(d.integer(forKey: "HUD.Ambient.timeout"))

        super.init()

        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "HUDAmbientCentral.v45"]
        )
    }

    func start() {
        guard central.state == .poweredOn else {
            status = "Waiting for Bluetooth"
            return
        }

        restoreRememberedPeripheralIfPossible()

        // Always scan from startup, even when a remembered peripheral exists.
        // A remembered CoreBluetooth connection can otherwise sit in
        // `.connecting` for minutes with no advertisement fallback.
        startScanning()

        if let trackedPeripheral {
            maintainConnection(to: trackedPeripheral, reason: "start")
        }

        startWatchdog()
    }

    func stop() {
        central.stopScan()
        watchdogTask?.cancel()
        watchdogTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil

        if let trackedPeripheral,
           trackedPeripheral.state == .connected ||
           trackedPeripheral.state == .connecting {
            central.cancelPeripheralConnection(trackedPeripheral)
        }

        status = "Stopped"
    }

    private func startScanning() {
        guard enabled, central.state == .poweredOn else { return }
        status = "Scanning for \(targetName)…"
        logger.log(
            "AMBIENT BG",
            "Scanning BLE advertisements for \(targetName); background mode enabled"
        )

        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    private func restoreRememberedPeripheralIfPossible() {
        guard trackedPeripheral == nil,
              let raw = UserDefaults.standard.string(forKey: peripheralIDKey),
              let uuid = UUID(uuidString: raw) else { return }

        if let peripheral = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            trackedPeripheral = peripheral
            detectedIdentifier = peripheral.identifier.uuidString
            detectedName = peripheral.name ?? targetName
            logger.log(
                "AMBIENT BG",
                "Retrieved remembered \(detectedName) \(detectedIdentifier)"
            )
        }
    }

    private func maintainConnection(to peripheral: CBPeripheral, reason: String) {
        guard enabled, central.state == .poweredOn else { return }

        switch peripheral.state {
        case .connected:
            markPresent(
                name: peripheral.name ?? detectedName,
                identifier: peripheral.identifier.uuidString,
                rssi: lastRSSI,
                reason: "persistent GATT connection"
            )
        case .connecting:
            status = "\(peripheral.name ?? targetName) connecting…"
        case .disconnected, .disconnecting:
            status = "\(peripheral.name ?? targetName) background watch connecting…"
            connectionAttemptStartedAt = Date()
            logger.log(
                "AMBIENT BG",
                "Requesting persistent connection to \(peripheral.identifier) reason=\(reason)"
            )
            central.connect(peripheral, options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
            ])
        @unknown default:
            break
        }
    }

    private func markPresent(
        name: String,
        identifier: String,
        rssi: Int?,
        reason: String
    ) {
        lastSeen = Date()
        detectedName = name
        detectedIdentifier = identifier
        if let rssi { lastRSSI = rssi }

        status = rssi.map { "\(name) present • RSSI \($0)" } ?? "\(name) present"

        let becamePresent = !lightPresent
        lightPresent = true

        if becamePresent {
            logger.log(
                "AMBIENT",
                "\(name) became present via \(reason); enabling HUD auto brightness"
            )
        }

        if bluetooth.state == .connected,
           becamePresent || Date().timeIntervalSince(lastHUDReassertAt) >= 5 {
            bluetooth.enqueue(
                HudCommands.autoBrightness(true),
                label: becamePresent
                    ? "Ambient trigger → Auto brightness ON"
                    : "Ambient presence reassert → Auto brightness ON"
            )
            lastHUDReassertAt = Date()
        }
    }

    private func markAbsent(reason: String) {
        guard lightPresent else { return }
        lightPresent = false
        status = "\(targetName) absent"
        logger.log(
            "AMBIENT",
            "\(targetName) became absent via \(reason); disabling HUD auto brightness"
        )
        if bluetooth.state == .connected {
            bluetooth.enqueue(
                HudCommands.autoBrightness(false),
                label: "Ambient trigger → Auto brightness OFF"
            )
        }
    }

    func rehydrateHUDState() {
        guard enabled, bluetooth.state == .connected else { return }

        let connectedPresence = trackedPeripheral?.state == .connected
        let recentAdvertisement =
            Date().timeIntervalSince(lastSeen) <=
            Double(max(1, absenceTimeoutSeconds) * absenceConfirmationWindows)

        let shouldEnable = lightPresent && (connectedPresence || recentAdvertisement)

        bluetooth.enqueue(
            HudCommands.autoBrightness(shouldEnable),
            label: "HUD rehydrate → ambient auto brightness \(shouldEnable ? "ON" : "OFF")"
        )

        logger.log(
            "AMBIENT SESSION",
            "Rehydrated brightness connectedPresence=\(connectedPresence) recentAdvertisement=\(recentAdvertisement)"
        )
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String : Any]
    ) {
        Task { @MainActor in
            self.logger.log("AMBIENT BG", "CoreBluetooth restored ambient central state")

            if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
               let peripheral = peripherals.first {
                self.trackedPeripheral = peripheral
                self.detectedIdentifier = peripheral.identifier.uuidString
                self.detectedName = peripheral.name ?? self.targetName
                UserDefaults.standard.set(
                    peripheral.identifier.uuidString,
                    forKey: self.peripheralIDKey
                )
            }

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

            self.trackedPeripheral = peripheral
            UserDefaults.standard.set(
                peripheral.identifier.uuidString,
                forKey: self.peripheralIDKey
            )

            self.markPresent(
                name: name,
                identifier: peripheral.identifier.uuidString,
                rssi: RSSI.intValue,
                reason: "advertisement"
            )

            // Marking presence happens immediately on the advertisement;
            // don't wait for the slower GATT connection. Keep a connection
            // pending as the background/locked-screen presence channel.
            // Scanning is stopped only after didConnect.
            self.maintainConnection(to: peripheral, reason: "matched advertisement")
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        Task { @MainActor in
            self.trackedPeripheral = peripheral
            UserDefaults.standard.set(
                peripheral.identifier.uuidString,
                forKey: self.peripheralIDKey
            )
            self.markPresent(
                name: peripheral.name ?? self.targetName,
                identifier: peripheral.identifier.uuidString,
                rssi: self.lastRSSI,
                reason: "CoreBluetooth didConnect"
            )
            self.connectionAttemptStartedAt = nil
            self.logger.log(
                "AMBIENT BG",
                "Persistent ambient BLE connection established; hybrid discovery remains armed"
            )
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.connectionAttemptStartedAt = nil
            self.logger.log(
                "AMBIENT BG",
                "Ambient connection failed: \(error?.localizedDescription ?? "unknown")"
            )
            self.scheduleConnectionRetry()
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            guard self.enabled else { return }
            self.connectionAttemptStartedAt = nil

            self.logger.log(
                "AMBIENT BG",
                "Ambient peripheral disconnected: \(error?.localizedDescription ?? "device unavailable")"
            )

            // A GATT disconnect is an OS-delivered event and therefore remains
            // useful when the app is backgrounded/locked. Turn brightness OFF,
            // then leave another pending connect request so device power-on
            // automatically wakes/reconnects us.
            self.markAbsent(reason: "persistent BLE disconnect")

            // Hybrid recovery: leave a GATT connection pending AND scan for
            // the remembered BLEDOM advertisement. If iOS delivers an
            // advertisement before GATT finishes, brightness turns ON
            // immediately rather than waiting ~10 seconds for didConnect.
            self.startScanning()
            self.scheduleConnectionRetry()
        }
    }

    private func scheduleConnectionRetry() {
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, self.enabled else { return }

            if let peripheral = self.trackedPeripheral {
                self.maintainConnection(to: peripheral, reason: "automatic retry")
            } else {
                self.startScanning()
            }
        }
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard self.enabled else { continue }

                if self.trackedPeripheral?.state == .connecting,
                   let started = self.connectionAttemptStartedAt,
                   Date().timeIntervalSince(started) > 6 {
                    self.logger.log(
                        "AMBIENT BG",
                        "Persistent connection stuck >6s; cancelling and returning to hybrid scan"
                    )
                    if let peripheral = self.trackedPeripheral {
                        self.central.cancelPeripheralConnection(peripheral)
                    }
                    self.connectionAttemptStartedAt = nil
                    self.startScanning()
                    self.scheduleConnectionRetry()
                    continue
                }

                if self.trackedPeripheral?.state != .connected {
                    self.startScanning()
                }

                let connected = self.trackedPeripheral?.state == .connected
                let elapsed = Date().timeIntervalSince(self.lastSeen)
                let timeout = Double(max(1, self.absenceTimeoutSeconds))
                let missedWindows = Int(elapsed / timeout)

                if self.lightPresent && !connected &&
                    missedWindows >= self.absenceConfirmationWindows {
                    self.markAbsent(
                        reason: "\(self.absenceConfirmationWindows) missed advertisement windows"
                    )
                }

                if self.lightPresent,
                   connected || elapsed <= timeout * Double(self.absenceConfirmationWindows),
                   self.bluetooth.state == .connected,
                   Date().timeIntervalSince(self.lastHUDReassertAt) >= 10 {
                    self.bluetooth.enqueue(
                        HudCommands.autoBrightness(true),
                        label: "Ambient watchdog reassert → Auto brightness ON"
                    )
                    self.lastHUDReassertAt = Date()
                }
            }
        }
    }

}

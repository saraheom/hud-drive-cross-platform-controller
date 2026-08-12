import Foundation
import CoreBluetooth
import UIKit
import Observation

@MainActor
@Observable
final class HudBluetoothManager: NSObject {
    enum State: String {
        case idle = "Disconnected"
        case scanning = "Scanning…"
        case connecting = "Connecting…"
        case connected = "Connected"
    }

    struct Device: Identifiable, Hashable {
        let id: UUID
        let name: String
        let rssi: Int
        let peripheral: CBPeripheral

        static func == (lhs: Device, rhs: Device) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private(set) var state: State = .idle
    private(set) var devices: [Device] = []
    private(set) var connectedName: String?
    private(set) var lastRX: String = ""
    private(set) var ancsAuthorized = false

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?
    private var txQueue: [(Data, String)] = []
    private var currentChunks: [Data] = []
    private var currentLabel = ""
    private var writing = false

    private let savedPeripheralIDKey = "HUD.savedPeripheralIdentifier"
    private let savedPeripheralNameKey = "HUD.savedPeripheralName"
    private var attemptedSavedReconnect = false

    // App-level reconnect watchdog. We intentionally keep CoreBluetooth
    // connection options=nil because that is the known-good physical-device path.
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var userRequestedDisconnect = false
    private var autoReconnectEnabled = true

    var savedHUDName: String? {
        UserDefaults.standard.string(forKey: savedPeripheralNameKey)
    }

    var reconnectStatus: String {
        if userRequestedDisconnect { return "Paused by user" }
        if reconnectTask != nil { return "Retrying automatically" }
        return autoReconnectEnabled ? "Enabled" : "Disabled"
    }

    let logger: LogManager

    init(logger: LogManager) {
        self.logger = logger
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: "HUDControllerCentral"
        ])
    }

    private func saveConnectedHUD(_ peripheral: CBPeripheral) {
        UserDefaults.standard.set(
            peripheral.identifier.uuidString,
            forKey: savedPeripheralIDKey
        )
        UserDefaults.standard.set(
            peripheral.name ?? "HUD Drive",
            forKey: savedPeripheralNameKey
        )
        logger.log(
            "BLE MEMORY",
            "Saved HUD \(peripheral.name ?? "HUD Drive") | \(peripheral.identifier)"
        )
        reconnectAttempt = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        userRequestedDisconnect = false
        autoReconnectEnabled = true
    }

    func forgetSavedHUD() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        autoReconnectEnabled = false
        userRequestedDisconnect = true
        UserDefaults.standard.removeObject(forKey: savedPeripheralIDKey)
        UserDefaults.standard.removeObject(forKey: savedPeripheralNameKey)
        logger.log("BLE MEMORY", "Forgot saved HUD and stopped auto-reconnect")
    }

    func reconnectSavedHUD() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        userRequestedDisconnect = false
        autoReconnectEnabled = true
        attemptedSavedReconnect = false
        reconnectSavedHUDIfPossible()
    }

    private func reconnectSavedHUDIfPossible() {
        guard central.state == .poweredOn else {
            logger.log("BLE AUTO", "Reconnect deferred: Bluetooth is not powered on")
            return
        }
        guard autoReconnectEnabled, !userRequestedDisconnect else {
            logger.log("BLE AUTO", "Reconnect skipped: disabled or user-requested disconnect")
            return
        }
        guard state != .connected && state != .connecting else { return }

        guard let raw = UserDefaults.standard.string(forKey: savedPeripheralIDKey),
              let uuid = UUID(uuidString: raw) else {
            logger.log("BLE AUTO", "No previously saved HUD")
            return
        }

        logger.log("BLE AUTO", "Looking for saved HUD \(raw)")
        let retrieved = central.retrievePeripherals(withIdentifiers: [uuid])

        guard let saved = retrieved.first else {
            logger.log("BLE AUTO", "Saved HUD is not currently retrievable")
            scheduleReconnect(reason: "saved peripheral not retrievable")
            return
        }

        let name = saved.name
            ?? UserDefaults.standard.string(forKey: savedPeripheralNameKey)
            ?? "HUD Drive"

        logger.log(
            "BLE AUTO",
            "Retrieved \(name); auto-connect attempt \(reconnectAttempt + 1) using options=nil"
        )

        peripheral = saved
        saved.delegate = self
        state = .connecting
        central.connect(saved, options: nil)
    }

    private func scheduleReconnect(reason: String) {
        guard autoReconnectEnabled, !userRequestedDisconnect else { return }
        guard reconnectTask == nil else { return }
        guard central.state == .poweredOn else { return }

        // 1s, 2s, 4s, 8s, 15s, then 30s thereafter.
        let delays: [Double] = [1, 2, 4, 8, 15, 30]
        let delay = delays[min(reconnectAttempt, delays.count - 1)]
        reconnectAttempt += 1

        logger.log(
            "BLE AUTO",
            "Scheduling reconnect in \(Int(delay))s (reason: \(reason), attempt \(reconnectAttempt))"
        )

        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.reconnectTask = nil
            self.reconnectSavedHUDIfPossible()
        }
    }

    private func cancelReconnect(reason: String) {
        if reconnectTask != nil {
            logger.log("BLE AUTO", "Cancelled pending reconnect: \(reason)")
        }
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    func scan() {
        userRequestedDisconnect = false
        autoReconnectEnabled = true
        cancelReconnect(reason: "manual scan")
        guard central.state == .poweredOn else {
            logger.log("BLE", "Cannot scan: Bluetooth state \(central.state.rawValue)")
            return
        }
        devices.removeAll()
        state = .scanning
        logger.log("BLE", "Scanning for all BLE advertisers (HUD is name-prioritized; NUS verified after connection)")
        // Do not filter by the Nordic UART service at discovery time.
        // HUD Drive does not reliably include the NUS UUID in its advertising
        // packet. Windows testing showed that it can advertise only its local
        // name, then expose NUS after GATT connection.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        Task {
            try? await Task.sleep(for: .seconds(8))
            await MainActor.run {
                self.central.stopScan()
                if self.state == .scanning { self.state = .idle }
                self.logger.log("BLE", "Scan complete: \(self.devices.count) named BLE device(s) shown in picker")
                if self.devices.isEmpty {
                    self.logger.log("BLE", "No named devices discovered. Check Bluetooth permission and that HUD is powered/not connected to another phone.")
                }
            }
        }
    }

    func connect(_ device: Device) {
        cancelReconnect(reason: "manual connect")
        reconnectAttempt = 0
        userRequestedDisconnect = false
        autoReconnectEnabled = true
        central.stopScan()
        state = .connecting
        peripheral = device.peripheral
        peripheral?.delegate = self
        logger.log("BLE", "Connecting to \(device.name) with baseline CoreBluetooth options=nil")
        logger.log("ANCS", "Pre-connect ANCS authorization state = \(device.peripheral.ancsAuthorized)")
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        logger.log("BLE", "User requested disconnect; automatic reconnect paused")
        userRequestedDisconnect = true
        autoReconnectEnabled = false
        cancelReconnect(reason: "user requested disconnect")
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    func initializeHUD() {
        enqueue(HudCommands.systemTime(), label: "System time")
        enqueue(HudCommands.keepAlive(), label: "KeepAlive")
        enqueue(HudCommands.phoneName(UIDevice.current.name), label: "Phone name")
        enqueue(HudCommands.keepAlive(), label: "KeepAlive")
        enqueue(HudCommands.fullScreen(true), label: "Full screen")
        enqueue(HudCommands.navigationState(false), label: "Navigation OFF")
        enqueue(HudCommands.manualBrightness(50), label: "Brightness defaults")
        enqueue(HudCommands.keepAlive(), label: "KeepAlive")
    }

    func enqueue(_ packet: Data, label: String) {
        guard state == .connected else {
            logger.log("ERROR", "Cannot send \(label): not connected")
            return
        }
        txQueue.append((packet, label))
        pumpTX()
    }

    private func pumpTX() {
        guard !writing,
              currentChunks.isEmpty,
              !txQueue.isEmpty,
              let peripheral,
              let txCharacteristic else { return }

        let next = txQueue.removeFirst()
        currentLabel = next.1
        currentChunks = HudProtocol.chunks(next.0)
        logger.log("TX", "\(next.1): \(HudProtocol.hex(next.0))")
        writing = true
        writeNextChunk(peripheral: peripheral, characteristic: txCharacteristic)
    }

    private func writeNextChunk(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard !currentChunks.isEmpty else {
            writing = false
            currentLabel = ""
            pumpTX()
            return
        }

        guard peripheral.canSendWriteWithoutResponse else {
            // CoreBluetooth will call peripheralIsReady(toSendWriteWithoutResponse:)
            return
        }

        let chunk = currentChunks.removeFirst()
        logger.log("TX CHUNK", HudProtocol.hex(chunk))
        peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)

        // One chunk at a time; next chunk is released asynchronously to avoid
        // splicing packets on devices that consume NUS writes slowly.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            self.writeNextChunk(peripheral: peripheral, characteristic: characteristic)
        }
    }

    private func onUARTEvent() {
        logger.log("HUD EVENT", "UART connection event -> queue KeepAlive")
        enqueue(HudCommands.keepAlive(), label: "Auto KeepAlive")
    }
}

extension HudBluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.logger.log("BLE", "Central state = \(central.state.rawValue)")
            if central.state == .poweredOn {
                self.attemptedSavedReconnect = false
                if self.autoReconnectEnabled && !self.userRequestedDisconnect {
                    self.reconnectSavedHUDIfPossible()
                }
            } else {
                self.cancelReconnect(reason: "Bluetooth state changed")
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String : Any],
                                    rssi RSSI: NSNumber) {
        Task { @MainActor in
            let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let name = peripheral.name ?? advertisedName ?? "(unnamed)"

            let advertisedServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
            let serviceText = advertisedServices.map(\.uuidString).joined(separator: ",")

            self.logger.log(
                "BLE FOUND",
                "\(name) | \(peripheral.identifier) | RSSI \(RSSI) | services=[\(serviceText)]"
            )

            // Keep the UI useful instead of filling it with every anonymous BLE
            // beacon. Always show named devices; HUD devices sort to the top.
            guard name != "(unnamed)" else { return }

            let device = Device(
                id: peripheral.identifier,
                name: name,
                rssi: RSSI.intValue,
                peripheral: peripheral
            )
            if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                self.devices[index] = device
            } else {
                self.devices.append(device)
            }

            self.devices.sort {
                let lhsHud = $0.name.localizedCaseInsensitiveContains("HUD")
                let rhsHud = $1.name.localizedCaseInsensitiveContains("HUD")
                if lhsHud != rhsHud { return lhsHud && !rhsHud }
                return $0.rssi > $1.rssi
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.logger.log("BLE", "GATT connected: \(peripheral.name ?? peripheral.identifier.uuidString)")
            self.cancelReconnect(reason: "GATT connected")
            self.reconnectAttempt = 0
            self.userRequestedDisconnect = false
            self.autoReconnectEnabled = true
            self.connectedName = peripheral.name ?? "HUD Drive"
            self.ancsAuthorized = peripheral.ancsAuthorized
            self.logger.log("ANCS", "Post-connect ancsAuthorized = \(peripheral.ancsAuthorized)")
            self.saveConnectedHUD(peripheral)
            peripheral.delegate = self
            peripheral.discoverServices([CBUUID(string: HudProtocol.serviceUUID)])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.state = .idle
            self.logger.log(
                "BLE ERROR",
                "Failed to connect \(peripheral.name ?? peripheral.identifier.uuidString): \(error?.localizedDescription ?? "unknown error")"
            )
            if self.autoReconnectEnabled && !self.userRequestedDisconnect {
                self.scheduleReconnect(reason: "connection attempt failed")
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didUpdateANCSAuthorizationFor peripheral: CBPeripheral) {
        Task { @MainActor in
            self.ancsAuthorized = peripheral.ancsAuthorized
            self.logger.log(
                "ANCS",
                "Authorization changed: ancsAuthorized = \(peripheral.ancsAuthorized)"
            )
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.state = .idle
            self.connectedName = nil
            self.ancsAuthorized = false
            self.txCharacteristic = nil
            self.rxCharacteristic = nil
            self.txQueue.removeAll()
            self.currentChunks.removeAll()
            self.writing = false
            let reason = error?.localizedDescription ?? "no error"
            self.logger.log("BLE", "Disconnected: \(reason)")

            if self.userRequestedDisconnect {
                self.logger.log("BLE AUTO", "No reconnect: disconnect was user-requested")
            } else if self.autoReconnectEnabled {
                self.scheduleReconnect(reason: "unexpected disconnect: \(reason)")
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    willRestoreState dict: [String : Any]) {
        Task { @MainActor in
            self.logger.log("BLE", "CoreBluetooth restoration callback")
            if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
               let restored = peripherals.first {
                self.logger.log(
                    "BLE AUTO",
                    "Restored peripheral \(restored.name ?? restored.identifier.uuidString)"
                )
                self.peripheral = restored
                restored.delegate = self
                self.saveConnectedHUD(restored)
            }
        }
    }
}

extension HudBluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error { self.logger.log("ERROR", "Service discovery: \(error.localizedDescription)") }
            guard let service = peripheral.services?.first(where: {
                $0.uuid == CBUUID(string: HudProtocol.serviceUUID)
            }) else {
                self.logger.log("ERROR", "HUD NUS service not found")
                return
            }
            peripheral.discoverCharacteristics([
                CBUUID(string: HudProtocol.writeUUID),
                CBUUID(string: HudProtocol.notifyUUID)
            ], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        Task { @MainActor in
            if let error { self.logger.log("ERROR", "Characteristic discovery: \(error.localizedDescription)") }
            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == CBUUID(string: HudProtocol.writeUUID) {
                    self.txCharacteristic = characteristic
                } else if characteristic.uuid == CBUUID(string: HudProtocol.notifyUUID) {
                    self.rxCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            if self.txCharacteristic != nil && self.rxCharacteristic != nil {
                self.state = .connected
                self.cancelReconnect(reason: "HUD transport ready")
                self.reconnectAttempt = 0
                self.logger.log("BLE", "HUD transport ready; reconnect watchdog armed")
                self.enqueue(HudCommands.uartConnectionCheck(), label: "UART connection check")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor in
            guard let data = characteristic.value else { return }
            self.lastRX = HudProtocol.hex(data)
            self.logger.log("RX", self.lastRX)
            if HudProtocol.isUARTConnectionEvent(data) {
                self.onUARTEvent()
            }
        }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        Task { @MainActor in
            guard let characteristic = self.txCharacteristic else { return }
            self.writeNextChunk(peripheral: peripheral, characteristic: characteristic)
        }
    }
}

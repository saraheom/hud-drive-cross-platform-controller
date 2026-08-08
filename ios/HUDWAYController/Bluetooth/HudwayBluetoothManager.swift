import Foundation
import CoreBluetooth
import UIKit
import Observation

@MainActor
@Observable
final class HudwayBluetoothManager: NSObject {
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

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?
    private var txQueue: [(Data, String)] = []
    private var currentChunks: [Data] = []
    private var currentLabel = ""
    private var writing = false

    let logger: LogManager

    init(logger: LogManager) {
        self.logger = logger
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: "HUDWAYControllerCentral"
        ])
    }

    func scan() {
        guard central.state == .poweredOn else {
            logger.log("BLE", "Cannot scan: Bluetooth state \(central.state.rawValue)")
            return
        }
        devices.removeAll()
        state = .scanning
        logger.log("BLE", "Scanning for HUDWAY Drive")
        central.scanForPeripherals(
            withServices: [CBUUID(string: HudwayProtocol.serviceUUID)],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        Task {
            try? await Task.sleep(for: .seconds(8))
            await MainActor.run {
                self.central.stopScan()
                if self.state == .scanning { self.state = .idle }
                self.logger.log("BLE", "Scan complete: \(self.devices.count) HUD-compatible device(s)")
            }
        }
    }

    func connect(_ device: Device) {
        central.stopScan()
        state = .connecting
        peripheral = device.peripheral
        peripheral?.delegate = self
        logger.log("BLE", "Connecting to \(device.name)")
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    func initializeHUD() {
        enqueue(HudwayCommands.systemTime(), label: "System time")
        enqueue(HudwayCommands.keepAlive(), label: "KeepAlive")
        enqueue(HudwayCommands.phoneName(UIDevice.current.name), label: "Phone name")
        enqueue(HudwayCommands.keepAlive(), label: "KeepAlive")
        enqueue(HudwayCommands.fullScreen(true), label: "Full screen")
        enqueue(HudwayCommands.navigationState(false), label: "Navigation OFF")
        enqueue(HudwayCommands.manualBrightness(50), label: "Brightness defaults")
        enqueue(HudwayCommands.keepAlive(), label: "KeepAlive")
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
        currentChunks = HudwayProtocol.chunks(next.0)
        logger.log("TX", "\(next.1): \(HudwayProtocol.hex(next.0))")
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
        logger.log("TX CHUNK", HudwayProtocol.hex(chunk))
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
        enqueue(HudwayCommands.keepAlive(), label: "Auto KeepAlive")
    }
}

extension HudwayBluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.logger.log("BLE", "Central state = \(central.state.rawValue)")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String : Any],
                                    rssi RSSI: NSNumber) {
        Task { @MainActor in
            let name = peripheral.name
                ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
                ?? "HUDWAY Drive"
            let device = Device(id: peripheral.identifier, name: name, rssi: RSSI.intValue, peripheral: peripheral)
            if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                self.devices[index] = device
            } else {
                self.devices.append(device)
            }
            self.devices.sort { ($0.name.contains("HUDWAY") ? 0 : 1, -$0.rssi) < ($1.name.contains("HUDWAY") ? 0 : 1, -$1.rssi) }
            self.logger.log("BLE FOUND", "\(name) | \(peripheral.identifier) | RSSI \(RSSI)")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.logger.log("BLE", "GATT connected: \(peripheral.name ?? peripheral.identifier.uuidString)")
            self.connectedName = peripheral.name ?? "HUDWAY Drive"
            peripheral.delegate = self
            peripheral.discoverServices([CBUUID(string: HudwayProtocol.serviceUUID)])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.state = .idle
            self.connectedName = nil
            self.txCharacteristic = nil
            self.rxCharacteristic = nil
            self.txQueue.removeAll()
            self.currentChunks.removeAll()
            self.writing = false
            self.logger.log("BLE", "Disconnected: \(error?.localizedDescription ?? "no error")")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    willRestoreState dict: [String : Any]) {
        Task { @MainActor in
            self.logger.log("BLE", "CoreBluetooth restoration callback")
        }
    }
}

extension HudwayBluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error { self.logger.log("ERROR", "Service discovery: \(error.localizedDescription)") }
            guard let service = peripheral.services?.first(where: {
                $0.uuid == CBUUID(string: HudwayProtocol.serviceUUID)
            }) else {
                self.logger.log("ERROR", "HUDWAY NUS service not found")
                return
            }
            peripheral.discoverCharacteristics([
                CBUUID(string: HudwayProtocol.writeUUID),
                CBUUID(string: HudwayProtocol.notifyUUID)
            ], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        Task { @MainActor in
            if let error { self.logger.log("ERROR", "Characteristic discovery: \(error.localizedDescription)") }
            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == CBUUID(string: HudwayProtocol.writeUUID) {
                    self.txCharacteristic = characteristic
                } else if characteristic.uuid == CBUUID(string: HudwayProtocol.notifyUUID) {
                    self.rxCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            if self.txCharacteristic != nil && self.rxCharacteristic != nil {
                self.state = .connected
                self.logger.log("BLE", "HUD transport ready")
                self.enqueue(HudwayCommands.uartConnectionCheck(), label: "UART connection check")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor in
            guard let data = characteristic.value else { return }
            self.lastRX = HudwayProtocol.hex(data)
            self.logger.log("RX", self.lastRX)
            if HudwayProtocol.isUARTConnectionEvent(data) {
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

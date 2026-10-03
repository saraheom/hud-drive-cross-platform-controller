import Foundation
import CoreBluetooth
import Observation

/// v90.35.3.24.22 diagnostic-only direct ELM327 feasibility probe.
///
/// This manager deliberately does not take OBD ownership away from the HUD. The
/// first field test asks a narrower question: can the iPhone establish a second
/// BLE/GATT connection to the user's existing ELM327 while the HUD keeps its
/// stock OBD session? No ELM reset or protocol-selection command is ever sent.
/// The only OBD command exposed by this diagnostic is one explicit `01 0D\r`
/// vehicle-speed request initiated by the user while parked/testing.
@MainActor
@Observable
final class DirectELM327Manager: NSObject {
    struct Device: Identifiable, Hashable {
        let id: UUID
        var name: String
        var rssi: Int
        var connectable: Bool
        var advertisedServices: [String]
    }

    private(set) var devices: [Device] = []
    var selectedDeviceID: UUID?
    private(set) var bluetoothState = "Initializing Bluetooth…"
    private(set) var status = "Not scanned"
    private(set) var connectedName: String?
    private(set) var gattSummary = "—"
    private(set) var txSummary = "—"
    private(set) var rxSummary = "—"
    private(set) var lastRX = "—"
    private(set) var speedProbeSummary = "Not run"
    private(set) var scanning = false
    private(set) var connecting = false
    private(set) var gattReady = false

    var hudOBDConnectedProvider: (() -> Bool)?
    var gpsSpeedMphProvider: (() -> Int)?

    private let logger: LogManager
    private let diagnostics: LiveMapDiagnosticRecorder
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristics: [CBCharacteristic] = []
    private var scanStopTask: Task<Void, Never>?
    private var speedProbeTimeoutTask: Task<Void, Never>?
    private var speedProbeActive = false
    private var speedProbeBuffer = ""
    private var hudOBDBeforeConnect: Bool?
    private var hudOBDBeforeProbe: Bool?

    init(logger: LogManager, diagnostics: LiveMapDiagnosticRecorder) {
        self.logger = logger
        self.diagnostics = diagnostics
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func scan() {
        guard central.state == .poweredOn else {
            status = "Bluetooth unavailable"
            emit("ELM SCAN", "scan rejected centralState=\(central.state.rawValue)", event: "scan_rejected")
            return
        }
        scanStopTask?.cancel()
        devices.removeAll()
        peripherals.removeAll()
        selectedDeviceID = nil
        scanning = true
        status = "Scanning for BLE OBD/ELM327 devices…"
        let hudOBD = hudOBDConnectedProvider?() ?? false
        emit("ELM SCAN", "BEGIN passive discovery hudOBDConnected=\(hudOBD ? 1 : 0); no connection/no OBD commands", event: "scan_begin", fields: ["hud_obd_connected": hudOBD])
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled else { return }
            self.stopScan(reason: "10s bounded scan complete")
        }
    }

    func stopScan(reason: String = "manual") {
        scanStopTask?.cancel(); scanStopTask = nil
        guard scanning else { return }
        central.stopScan()
        scanning = false
        status = devices.isEmpty ? "Scan complete • no named BLE devices found" : "Scan complete • \(devices.count) device(s)"
        emit("ELM SCAN", "END reason=\(reason) devices=\(devices.count)", event: "scan_end", fields: ["reason": reason, "devices": devices.count])
    }

    func selectAndConnect(_ id: UUID?) {
        selectedDeviceID = id
        guard id != nil else { return }
        emit("ELM CONN", "user selected device; automatic connection attempt", event: "selection_auto_connect")
        connectSelected()
    }

    func connectSelected() {
        guard let id = selectedDeviceID, let peripheral = peripherals[id] else {
            status = "Select a device first"
            return
        }
        stopScan(reason: "connect requested")
        if let existing = connectedPeripheral, existing.identifier != peripheral.identifier {
            central.cancelPeripheralConnection(existing)
        }
        hudOBDBeforeConnect = hudOBDConnectedProvider?() ?? false
        connecting = true
        gattReady = false
        txCharacteristic = nil
        rxCharacteristics.removeAll()
        status = "Connecting to \(peripheral.name ?? id.uuidString)…"
        emit(
            "ELM CONN",
            "BEGIN device=\(peripheral.name ?? id.uuidString) id=\(id) hudOBDBefore=\((hudOBDBeforeConnect ?? false) ? 1 : 0) coexistenceTest=1",
            event: "connect_begin",
            fields: ["device": peripheral.name ?? id.uuidString, "id": id.uuidString, "hud_obd_before": hudOBDBeforeConnect ?? false]
        )
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        speedProbeTimeoutTask?.cancel(); speedProbeTimeoutTask = nil
        speedProbeActive = false
        guard let peripheral = connectedPeripheral else {
            status = "Disconnected"
            connectedName = nil
            return
        }
        emit("ELM CONN", "user disconnect device=\(peripheral.name ?? peripheral.identifier.uuidString)", event: "disconnect_requested")
        central.cancelPeripheralConnection(peripheral)
    }

    /// Sends one standard OBD-II Mode 01 PID 0D request. No AT reset or protocol
    /// command is sent. Production Map Mode speed remains GPS in this release.
    func runOneShotVehicleSpeedProbe() {
        guard let peripheral = connectedPeripheral, let txCharacteristic else {
            speedProbeSummary = "Not ready • connect and discover writable GATT first"
            return
        }
        guard !speedProbeActive else {
            speedProbeSummary = "Probe already in progress"
            return
        }
        let command = "010D\r"
        guard let bytes = command.data(using: .ascii) else { return }
        let writeType: CBCharacteristicWriteType
        if txCharacteristic.properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else if txCharacteristic.properties.contains(.write) {
            writeType = .withResponse
        } else {
            speedProbeSummary = "Selected TX characteristic is not writable"
            return
        }

        speedProbeActive = true
        speedProbeBuffer = ""
        hudOBDBeforeProbe = hudOBDConnectedProvider?() ?? false
        let gps = gpsSpeedMphProvider?() ?? 0
        speedProbeSummary = "Sent 01 0D • waiting for 41 0D XX"
        emit(
            "ELM TX",
            "ASCII=010D\\r hex=30 31 30 44 0D writeType=\(writeType == .withoutResponse ? "withoutResponse" : "withResponse") hudOBDBefore=\((hudOBDBeforeProbe ?? false) ? 1 : 0) gps=\(gps)mph; NO ATZ/ATSP command",
            event: "speed_probe_tx",
            fields: ["command": "010D\\r", "hud_obd_before": hudOBDBeforeProbe ?? false, "gps_mph": gps]
        )
        peripheral.writeValue(bytes, for: txCharacteristic, type: writeType)

        speedProbeTimeoutTask?.cancel()
        speedProbeTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled, self.speedProbeActive else { return }
            self.speedProbeActive = false
            let hudAfter = self.hudOBDConnectedProvider?() ?? false
            self.speedProbeSummary = "Timed out • no validated 41 0D response"
            self.emit(
                "ELM SPEED",
                "TIMEOUT raw={\(self.speedProbeBuffer)} hudOBDBefore=\((self.hudOBDBeforeProbe ?? false) ? 1 : 0) hudOBDAfter=\(hudAfter ? 1 : 0)",
                event: "speed_probe_timeout",
                fields: ["raw": self.speedProbeBuffer, "hud_obd_before": self.hudOBDBeforeProbe ?? false, "hud_obd_after": hudAfter]
            )
        }
    }

    private func considerSpeedResponse(_ text: String) {
        guard speedProbeActive else { return }
        speedProbeBuffer += text
        let normalized = speedProbeBuffer
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: ">", with: "")
        guard let range = normalized.range(of: "410D") else { return }
        let suffix = normalized[range.upperBound...]
        guard suffix.count >= 2 else { return }
        let hex = String(suffix.prefix(2))
        guard let kmh = Int(hex, radix: 16) else { return }

        speedProbeActive = false
        speedProbeTimeoutTask?.cancel(); speedProbeTimeoutTask = nil
        let mph = Int((Double(kmh) * 0.621371).rounded())
        let gps = gpsSpeedMphProvider?() ?? 0
        let hudAfter = hudOBDConnectedProvider?() ?? false
        let delta = mph - gps
        speedProbeSummary = "Validated 41 0D \(hex) • \(kmh) km/h • \(mph) mph • GPS \(gps) mph"
        emit(
            "ELM SPEED",
            "VALID response=41 0D \(hex) speed=\(kmh)kmh/\(mph)mph gps=\(gps)mph delta=\(delta) hudOBDBefore=\((hudOBDBeforeProbe ?? false) ? 1 : 0) hudOBDAfter=\(hudAfter ? 1 : 0)",
            event: "speed_probe_valid",
            fields: [
                "response": "41 0D \(hex)",
                "kmh": kmh,
                "mph": mph,
                "gps_mph": gps,
                "delta_mph": delta,
                "hud_obd_before": hudOBDBeforeProbe ?? false,
                "hud_obd_after": hudAfter
            ]
        )
    }

    private func chooseCharacteristics(for peripheral: CBPeripheral) {
        let chars = peripheral.services?.flatMap { $0.characteristics ?? [] } ?? []
        let writable = chars.filter { $0.properties.contains(.writeWithoutResponse) || $0.properties.contains(.write) }
        let notifying = chars.filter { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }

        // Generic ELM BLE clones commonly expose either a single bidirectional
        // UART characteristic or separate TX/RX characteristics. Prefer a
        // bidirectional characteristic, otherwise first writable + all notify.
        txCharacteristic = writable.first(where: {
            $0.properties.contains(.notify) || $0.properties.contains(.indicate)
        }) ?? writable.first
        rxCharacteristics = notifying
        if rxCharacteristics.isEmpty, let txCharacteristic,
           txCharacteristic.properties.contains(.read) {
            rxCharacteristics = [txCharacteristic]
        }

        for characteristic in notifying where !characteristic.isNotifying {
            peripheral.setNotifyValue(true, for: characteristic)
        }
        gattReady = txCharacteristic != nil && !rxCharacteristics.isEmpty
        txSummary = txCharacteristic.map { Self.characteristicDescription($0) } ?? "No writable characteristic"
        rxSummary = rxCharacteristics.isEmpty ? "No notify/indicate/read characteristic" : rxCharacteristics.map(Self.characteristicDescription).joined(separator: " | ")
        gattSummary = "services \(peripheral.services?.count ?? 0) • characteristics \(chars.count) • \(gattReady ? "probe-ready" : "incomplete")"
        emit(
            "ELM GATT",
            "discovery complete \(gattSummary) TX={\(txSummary)} RX={\(rxSummary)}",
            event: "gatt_ready",
            fields: ["services": peripheral.services?.count ?? 0, "characteristics": chars.count, "ready": gattReady, "tx": txSummary, "rx": rxSummary]
        )
    }

    private static func characteristicDescription(_ c: CBCharacteristic) -> String {
        var props: [String] = []
        if c.properties.contains(.read) { props.append("read") }
        if c.properties.contains(.write) { props.append("write") }
        if c.properties.contains(.writeWithoutResponse) { props.append("writeNoRsp") }
        if c.properties.contains(.notify) { props.append("notify") }
        if c.properties.contains(.indicate) { props.append("indicate") }
        return "\(c.service?.uuid.uuidString ?? "?")/\(c.uuid.uuidString)[\(props.joined(separator: ","))]"
    }

    private func emit(_ category: String, _ message: String, event: String, fields: [String: Any] = [:]) {
        logger.log(category, message)
        diagnostics.record("elm327", event, fields: fields.merging(["message": message]) { current, _ in current })
    }
}

extension DirectELM327Manager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.bluetoothState = String(describing: central.state)
            self.emit("ELM SCAN", "central state=\(central.state.rawValue)", event: "central_state", fields: ["state": central.state.rawValue])
            if central.state != .poweredOn {
                self.scanning = false
                self.status = "Bluetooth unavailable • state \(central.state.rawValue)"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let name = peripheral.name ?? advertisedName ?? "(unnamed)"
            guard name != "(unnamed)" else { return }
            let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
            let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true
            self.peripherals[peripheral.identifier] = peripheral
            let device = Device(id: peripheral.identifier, name: name, rssi: RSSI.intValue, connectable: connectable, advertisedServices: services)
            if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                self.devices[index] = device
            } else {
                self.devices.append(device)
            }
            self.devices.sort {
                let lhsOBD = $0.name.localizedCaseInsensitiveContains("OBD") || $0.name.localizedCaseInsensitiveContains("ELM")
                let rhsOBD = $1.name.localizedCaseInsensitiveContains("OBD") || $1.name.localizedCaseInsensitiveContains("ELM")
                if lhsOBD != rhsOBD { return lhsOBD && !rhsOBD }
                return $0.rssi > $1.rssi
            }
            if self.selectedDeviceID == nil,
               name.localizedCaseInsensitiveContains("OBD") || name.localizedCaseInsensitiveContains("ELM") {
                self.selectedDeviceID = peripheral.identifier
            }
            self.emit(
                "ELM SCAN",
                "FOUND name=\(name) id=\(peripheral.identifier) rssi=\(RSSI.intValue) connectable=\(connectable ? 1 : 0) services=[\(services.joined(separator: ","))] hudOBD=\((self.hudOBDConnectedProvider?() ?? false) ? 1 : 0)",
                event: "device_found",
                fields: ["name": name, "id": peripheral.identifier.uuidString, "rssi": RSSI.intValue, "connectable": connectable, "services": services]
            )
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.connecting = false
            self.connectedPeripheral = peripheral
            self.connectedName = peripheral.name ?? peripheral.identifier.uuidString
            self.status = "Connected • discovering GATT"
            peripheral.delegate = self
            let hudAfter = self.hudOBDConnectedProvider?() ?? false
            self.emit(
                "ELM CONN",
                "CONNECTED device=\(self.connectedName ?? "?") hudOBDBefore=\((self.hudOBDBeforeConnect ?? false) ? 1 : 0) hudOBDAfter=\(hudAfter ? 1 : 0)",
                event: "connected",
                fields: ["device": self.connectedName ?? "?", "hud_obd_before": self.hudOBDBeforeConnect ?? false, "hud_obd_after": hudAfter]
            )
            peripheral.discoverServices(nil)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.connectedPeripheral?.identifier == peripheral.identifier else { return }
                let delayed = self.hudOBDConnectedProvider?() ?? false
                self.emit("ELM CONN", "2s coexistence checkpoint hudOBD=\(delayed ? 1 : 0)", event: "coexistence_checkpoint", fields: ["hud_obd_connected": delayed])
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.connecting = false
            self.status = "Connection failed"
            self.emit("ELM CONN", "FAILED device=\(peripheral.name ?? peripheral.identifier.uuidString) error=\(error?.localizedDescription ?? "unknown") hudOBD=\((self.hudOBDConnectedProvider?() ?? false) ? 1 : 0)", event: "connect_failed", fields: ["error": error?.localizedDescription ?? "unknown"])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.speedProbeTimeoutTask?.cancel(); self.speedProbeTimeoutTask = nil
            self.speedProbeActive = false
            self.connecting = false
            self.connectedPeripheral = nil
            self.connectedName = nil
            self.txCharacteristic = nil
            self.rxCharacteristics.removeAll()
            self.gattReady = false
            self.gattSummary = "—"
            self.status = "Disconnected"
            self.emit("ELM CONN", "DISCONNECTED device=\(peripheral.name ?? peripheral.identifier.uuidString) error=\(error?.localizedDescription ?? "none") hudOBD=\((self.hudOBDConnectedProvider?() ?? false) ? 1 : 0)", event: "disconnected", fields: ["error": error?.localizedDescription ?? "none"])
        }
    }
}

extension DirectELM327Manager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                self.status = "Service discovery failed"
                self.emit("ELM GATT", "service discovery error=\(error.localizedDescription)", event: "service_error")
                return
            }
            let services = peripheral.services ?? []
            self.emit("ELM GATT", "services=[\(services.map { $0.uuid.uuidString }.joined(separator: ","))]", event: "services", fields: ["services": services.map { $0.uuid.uuidString }])
            for service in services { peripheral.discoverCharacteristics(nil, for: service) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                self.emit("ELM GATT", "characteristics error service=\(service.uuid.uuidString) error=\(error.localizedDescription)", event: "characteristic_error")
                return
            }
            let descriptions = (service.characteristics ?? []).map(Self.characteristicDescription)
            self.emit("ELM GATT", "service=\(service.uuid.uuidString) characteristics={\(descriptions.joined(separator: " | "))}", event: "characteristics", fields: ["service": service.uuid.uuidString, "characteristics": descriptions])
            self.chooseCharacteristics(for: peripheral)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                self.emit("ELM RX", "error characteristic=\(characteristic.uuid.uuidString) \(error.localizedDescription)", event: "rx_error")
                return
            }
            guard let data = characteristic.value else { return }
            let ascii = String(data: data, encoding: .ascii) ?? ""
            let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            self.lastRX = ascii.isEmpty ? hex : ascii.replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
            self.emit("ELM RX", "char=\(characteristic.uuid.uuidString) bytes=\(data.count) ascii={\(self.lastRX)} hex={\(hex)}", event: "rx", fields: ["characteristic": characteristic.uuid.uuidString, "bytes": data.count, "ascii": ascii, "hex": hex])
            if !ascii.isEmpty { self.considerSpeedResponse(ascii) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            self.emit("ELM TX", "write callback char=\(characteristic.uuid.uuidString) error=\(error?.localizedDescription ?? "none")", event: "write_callback", fields: ["error": error?.localizedDescription ?? "none"])
        }
    }
}

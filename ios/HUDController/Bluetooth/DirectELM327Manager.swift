import Foundation
import CoreBluetooth
import Observation

/// v90.35.3.24.28 direct ELM327 manager.
///
/// The October 5 field test proved the user's OBDII adapter is effectively
/// single-client: it becomes visible to iOS immediately after the HUD releases
/// ownership and returns valid SAE J1979 `41 0D XX` vehicle-speed responses.
/// This manager therefore supports both the original manual diagnostic surface
/// and production Map Mode ownership/polling. It never sends ATZ, ATSP, protocol
/// selection, reset, or any command other than `01 0D\r`.
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
    private(set) var mapModeOwnershipRequested = false
    private(set) var productionPolling = false
    private(set) var currentSpeedMph: Int?
    private(set) var currentSpeedKmh: Int?
    private(set) var lastSpeedAt: Date?
    private(set) var ownershipStatus = "HUD owns OBD"

    var hudOBDConnectedProvider: (() -> Bool)?
    var gpsSpeedMphProvider: (() -> Int)?

    private let logger: LogManager
    private let diagnostics: LiveMapDiagnosticRecorder
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var connectingPeripheral: CBPeripheral?
    /// A production Map-Mode connect is tagged with the ownership generation that
    /// requested it. CoreBluetooth may deliver didConnect after cancel/release;
    /// the generation gate makes such callbacks harmless instead of stealing the
    /// single-client ELM back from the HUD after Navigation/Freeride resumes.
    private var ownershipGeneration: UInt64 = 0
    private var productionConnectGeneration: [UUID: UInt64] = [:]
    /// IDs for which release/cancel has been requested but CoreBluetooth has not
    /// yet acknowledged failure/disconnect.  HUD reclaim waits on this set.
    private var releaseCancellationPendingIDs: Set<UUID> = []
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristics: [CBCharacteristic] = []
    private var scanStopTask: Task<Void, Never>?
    private var speedProbeTimeoutTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var ownershipConnectTask: Task<Void, Never>?
    private var speedProbeActive = false
    private var speedProbeBuffer = ""
    private var streamBuffer = ""
    private var hudOBDBeforeConnect: Bool?
    private var hudOBDBeforeProbe: Bool?
    private var lastProductionSpeedLogAt = Date.distantPast
    private var lastLoggedProductionSpeed: Int?
    private var autoConnectDiscoveredOBD = false

    private let savedPeripheralKey = "HUD.DirectELM.savedPeripheralUUID"
    private let savedNameKey = "HUD.DirectELM.savedPeripheralName"

    init(logger: LogManager, diagnostics: LiveMapDiagnosticRecorder) {
        self.logger = logger
        self.diagnostics = diagnostics
        if let raw = UserDefaults.standard.string(forKey: savedPeripheralKey), let uuid = UUID(uuidString: raw) {
            self.selectedDeviceID = uuid
        }
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var hasFreshProductionSpeed: Bool {
        guard let lastSpeedAt else { return false }
        return productionPolling && Date().timeIntervalSince(lastSpeedAt) <= 1.5
    }

    func freshSpeedMph(maxAge: TimeInterval = 1.5) -> Int? {
        guard let currentSpeedMph, let lastSpeedAt,
              Date().timeIntervalSince(lastSpeedAt) <= maxAge else { return nil }
        return currentSpeedMph
    }

    var speedSourceSummary: String {
        if let mph = freshSpeedMph() { return "OBD • \(mph) mph" }
        if mapModeOwnershipRequested { return productionPolling ? "OBD stale • GPS fallback" : "OBD connecting • GPS fallback" }
        return "HUD/stock ownership"
    }

    var fullyReleasedForHUD: Bool {
        !mapModeOwnershipRequested && !connecting && connectedPeripheral == nil && connectingPeripheral == nil && !productionPolling && releaseCancellationPendingIDs.isEmpty
    }

    func scan() {
        beginScan(duration: 10, productionAutoConnect: false)
    }

    private func beginScan(duration: TimeInterval, productionAutoConnect: Bool) {
        guard central.state == .poweredOn else {
            status = "Bluetooth unavailable"
            emit("ELM SCAN", "scan rejected centralState=\(central.state.rawValue)", event: "scan_rejected")
            return
        }
        scanStopTask?.cancel()
        devices.removeAll()
        peripherals.removeAll()
        if !productionAutoConnect { selectedDeviceID = nil }
        autoConnectDiscoveredOBD = productionAutoConnect
        scanning = true
        status = productionAutoConnect ? "Looking for saved OBDII…" : "Scanning for BLE OBD/ELM327 devices…"
        let hudOBD = hudOBDConnectedProvider?() ?? false
        emit(
            "ELM SCAN",
            "BEGIN discovery hudOBDConnected=\(hudOBD ? 1 : 0) production=\(productionAutoConnect ? 1 : 0); no AT/reset commands",
            event: "scan_begin",
            fields: ["hud_obd_connected": hudOBD, "production": productionAutoConnect]
        )
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int64(duration * 1000)))
            guard let self, !Task.isCancelled else { return }
            self.stopScan(reason: "bounded scan complete")
            if productionAutoConnect && self.mapModeOwnershipRequested && self.connectedPeripheral == nil {
                self.ownershipStatus = "OBD not found • GPS fallback"
                self.emit("OBD OWNERSHIP", "Map Mode direct OBD scan ended without connection; GPS fallback remains active", event: "map_obd_scan_miss")
            }
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
        connect(peripheral, production: mapModeOwnershipRequested)
    }

    private func connect(_ peripheral: CBPeripheral, production: Bool) {
        stopScan(reason: "connect requested")
        if let existing = connectedPeripheral, existing.identifier != peripheral.identifier {
            central.cancelPeripheralConnection(existing)
        }
        hudOBDBeforeConnect = hudOBDConnectedProvider?() ?? false
        connecting = true
        connectingPeripheral = peripheral
        if production {
            productionConnectGeneration[peripheral.identifier] = ownershipGeneration
        } else {
            productionConnectGeneration.removeValue(forKey: peripheral.identifier)
        }
        gattReady = false
        txCharacteristic = nil
        rxCharacteristics.removeAll()
        status = "Connecting to \(peripheral.name ?? peripheral.identifier.uuidString)…"
        emit(
            "ELM CONN",
            "BEGIN device=\(peripheral.name ?? peripheral.identifier.uuidString) id=\(peripheral.identifier) hudOBDBefore=\((hudOBDBeforeConnect ?? false) ? 1 : 0) production=\(production ? 1 : 0)",
            event: "connect_begin",
            fields: ["device": peripheral.name ?? peripheral.identifier.uuidString, "id": peripheral.identifier.uuidString, "hud_obd_before": hudOBDBeforeConnect ?? false, "production": production]
        )
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        stopPolling(reason: "manual disconnect")
        mapModeOwnershipRequested = false
        ownershipConnectTask?.cancel(); ownershipConnectTask = nil
        speedProbeTimeoutTask?.cancel(); speedProbeTimeoutTask = nil
        speedProbeActive = false
        ownershipGeneration &+= 1
        productionConnectGeneration.removeAll()
        if let pending = connectingPeripheral {
            central.cancelPeripheralConnection(pending)
            connectingPeripheral = nil
            connecting = false
        }
        guard let peripheral = connectedPeripheral else {
            status = "Disconnected"
            connectedName = nil
            return
        }
        emit("ELM CONN", "user disconnect device=\(peripheral.name ?? peripheral.identifier.uuidString)", event: "disconnect_requested")
        central.cancelPeripheralConnection(peripheral)
    }

    /// Called after AppState has told the HUD to release its single-client ELM link.
    /// Uses the remembered peripheral when available, otherwise performs a bounded
    /// scan and automatically connects to the first OBD/ELM candidate.
    func claimForMapMode() {
        if !mapModeOwnershipRequested { ownershipGeneration &+= 1 }
        mapModeOwnershipRequested = true
        ownershipStatus = "iPhone claiming OBD…"
        currentSpeedMph = nil
        currentSpeedKmh = nil
        lastSpeedAt = nil
        emit("OBD OWNERSHIP", "iPhone Map Mode ownership requested generation=\(ownershipGeneration) hudOBD=\((hudOBDConnectedProvider?() ?? false) ? 1 : 0)", event: "map_obd_claim", fields: ["ownership_generation": ownershipGeneration])

        if connectedPeripheral != nil {
            if gattReady { startPollingIfReady() }
            return
        }
        guard central.state == .poweredOn else {
            ownershipStatus = "Bluetooth unavailable • GPS fallback"
            return
        }

        if let raw = UserDefaults.standard.string(forKey: savedPeripheralKey), let uuid = UUID(uuidString: raw) {
            let recovered = central.retrievePeripherals(withIdentifiers: [uuid])
            if let peripheral = recovered.first {
                peripherals[uuid] = peripheral
                selectedDeviceID = uuid
                ownershipStatus = "Connecting saved \(peripheral.name ?? "OBDII")…"
                connect(peripheral, production: true)
                return
            }
        }
        beginScan(duration: 8, productionAutoConnect: true)
    }

    /// Releases the BLE link before the HUD resumes its normal OBD ownership.
    func releaseMapModeOwnership() {
        mapModeOwnershipRequested = false
        ownershipGeneration &+= 1 // invalidate every in-flight production connect callback
        ownershipStatus = "Returning OBD to HUD…"
        autoConnectDiscoveredOBD = false
        stopPolling(reason: "Map Mode ended")
        currentSpeedMph = nil
        currentSpeedKmh = nil
        lastSpeedAt = nil
        ownershipConnectTask?.cancel(); ownershipConnectTask = nil
        stopScan(reason: "Map Mode ended")
        let invalidated = productionConnectGeneration.count
        // Keep the production generation tags until CoreBluetooth reports the
        // callback.  The increment above makes every old tag stale; deleting the
        // tag here would make a late didConnect indistinguishable from a manual
        // connection and could steal the single-client ELM back from the HUD.
        if let pending = connectingPeripheral {
            releaseCancellationPendingIDs.insert(pending.identifier)
            emit("OBD OWNERSHIP", "Cancelling in-flight iPhone OBD connect before HUD reclaim peripheral=\(pending.name ?? pending.identifier.uuidString) generation=\(ownershipGeneration)", event: "map_obd_cancel_pending", fields: ["ownership_generation": ownershipGeneration])
            central.cancelPeripheralConnection(pending)
        }
        if let peripheral = connectedPeripheral {
            releaseCancellationPendingIDs.insert(peripheral.identifier)
            emit("OBD OWNERSHIP", "iPhone releasing OBD peripheral=\(peripheral.name ?? peripheral.identifier.uuidString) invalidatedPending=\(invalidated)", event: "map_obd_release", fields: ["invalidated_pending": invalidated, "ownership_generation": ownershipGeneration])
            central.cancelPeripheralConnection(peripheral)
        } else if connectingPeripheral == nil {
            ownershipStatus = "HUD may reclaim OBD"
        }
    }

    /// Release production ownership and wait for CoreBluetooth to confirm that
    /// no connected or in-flight production peripheral remains. The caller uses
    /// this barrier before re-enabling the HUD's OBD auto-connect loop.
    @discardableResult
    func releaseMapModeOwnershipAndWait(timeout: TimeInterval = 2.5) async -> Bool {
        releaseMapModeOwnership()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if fullyReleasedForHUD {
                ownershipStatus = "OBD released • HUD may reclaim"
                emit("OBD OWNERSHIP", "RELEASE CONFIRMED before HUD reconnect generation=\(ownershipGeneration)", event: "map_obd_release_confirmed", fields: ["ownership_generation": ownershipGeneration])
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let connected = connectedPeripheral?.identifier.uuidString ?? "none"
        let pending = connectingPeripheral?.identifier.uuidString ?? "none"
        emit("OBD OWNERSHIP", "RELEASE TIMEOUT before HUD reconnect connected=\(connected) pending=\(pending) cancelAck=\(releaseCancellationPendingIDs.count); late production callbacks remain generation-gated", event: "map_obd_release_timeout", fields: ["connected": connected, "pending": pending, "cancel_ack_pending": releaseCancellationPendingIDs.count, "ownership_generation": ownershipGeneration])
        return fullyReleasedForHUD
    }

    /// Manual parked probe retained for diagnostics. It sends exactly one `01 0D`.
    func runOneShotVehicleSpeedProbe() {
        guard let peripheral = connectedPeripheral, let txCharacteristic else {
            speedProbeSummary = "Not ready • connect and discover writable GATT first"
            return
        }
        guard !speedProbeActive else {
            speedProbeSummary = "Probe already in progress"
            return
        }
        speedProbeActive = true
        speedProbeBuffer = ""
        hudOBDBeforeProbe = hudOBDConnectedProvider?() ?? false
        let gps = gpsSpeedMphProvider?() ?? 0
        speedProbeSummary = "Sent 01 0D • waiting for 41 0D XX"
        emit("ELM TX", "ASCII=010D\\r oneShot=1 hudOBDBefore=\((hudOBDBeforeProbe ?? false) ? 1 : 0) gps=\(gps)mph; NO ATZ/ATSP command", event: "speed_probe_tx", fields: ["command": "010D\\r", "hud_obd_before": hudOBDBeforeProbe ?? false, "gps_mph": gps])
        guard sendVehicleSpeedRequest(peripheral: peripheral, characteristic: txCharacteristic) else {
            speedProbeActive = false
            speedProbeSummary = "Selected TX characteristic is not writable"
            return
        }
        speedProbeTimeoutTask?.cancel()
        speedProbeTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled, self.speedProbeActive else { return }
            self.speedProbeActive = false
            let hudAfter = self.hudOBDConnectedProvider?() ?? false
            self.speedProbeSummary = "Timed out • no validated 41 0D response"
            self.emit("ELM SPEED", "TIMEOUT raw={\(self.speedProbeBuffer)} hudOBDBefore=\((self.hudOBDBeforeProbe ?? false) ? 1 : 0) hudOBDAfter=\(hudAfter ? 1 : 0)", event: "speed_probe_timeout", fields: ["raw": self.speedProbeBuffer, "hud_obd_before": self.hudOBDBeforeProbe ?? false, "hud_obd_after": hudAfter])
        }
    }

    private func sendVehicleSpeedRequest(peripheral: CBPeripheral, characteristic: CBCharacteristic) -> Bool {
        guard let bytes = "010D\r".data(using: .ascii) else { return false }
        let writeType: CBCharacteristicWriteType
        if characteristic.properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else if characteristic.properties.contains(.write) {
            writeType = .withResponse
        } else {
            return false
        }
        peripheral.writeValue(bytes, for: characteristic, type: writeType)
        return true
    }

    private func startPollingIfReady() {
        guard mapModeOwnershipRequested, gattReady,
              let peripheral = connectedPeripheral, let txCharacteristic else { return }
        guard pollingTask == nil else { return }
        productionPolling = true
        ownershipStatus = "iPhone owns OBD • polling speed"
        emit("OBD OWNERSHIP", "Map Mode direct OBD polling START rate=5Hz command=010D only", event: "map_obd_poll_start")
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.mapModeOwnershipRequested,
                  self.connectedPeripheral?.identifier == peripheral.identifier {
                if !self.sendVehicleSpeedRequest(peripheral: peripheral, characteristic: txCharacteristic) {
                    self.ownershipStatus = "OBD write unavailable • GPS fallback"
                    break
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            self.productionPolling = false
            self.pollingTask = nil
        }
    }

    private func stopPolling(reason: String) {
        pollingTask?.cancel(); pollingTask = nil
        if productionPolling {
            emit("OBD OWNERSHIP", "Map Mode direct OBD polling STOP reason=\(reason)", event: "map_obd_poll_stop", fields: ["reason": reason])
        }
        productionPolling = false
    }

    private func considerSpeedResponse(_ text: String) {
        streamBuffer += text
        if streamBuffer.count > 512 { streamBuffer = String(streamBuffer.suffix(256)) }
        if speedProbeActive { speedProbeBuffer += text }

        let normalized = streamBuffer
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: ">", with: "")
        guard let range = normalized.range(of: "410D", options: .backwards) else { return }
        let suffix = normalized[range.upperBound...]
        guard suffix.count >= 2 else { return }
        let hex = String(suffix.prefix(2))
        guard let kmh = Int(hex, radix: 16) else { return }
        let mph = Int((Double(kmh) * 0.621371).rounded())
        currentSpeedKmh = kmh
        currentSpeedMph = mph
        lastSpeedAt = Date()

        let gps = gpsSpeedMphProvider?() ?? 0
        let hudAfter = hudOBDConnectedProvider?() ?? false
        if speedProbeActive {
            speedProbeActive = false
            speedProbeTimeoutTask?.cancel(); speedProbeTimeoutTask = nil
            let delta = mph - gps
            speedProbeSummary = "Validated 41 0D \(hex) • \(kmh) km/h • \(mph) mph • GPS \(gps) mph"
            emit("ELM SPEED", "VALID response=41 0D \(hex) speed=\(kmh)kmh/\(mph)mph gps=\(gps)mph delta=\(delta) hudOBDBefore=\((hudOBDBeforeProbe ?? false) ? 1 : 0) hudOBDAfter=\(hudAfter ? 1 : 0)", event: "speed_probe_valid", fields: ["response": "41 0D \(hex)", "kmh": kmh, "mph": mph, "gps_mph": gps, "delta_mph": delta, "hud_obd_before": hudOBDBeforeProbe ?? false, "hud_obd_after": hudAfter])
        }

        if productionPolling {
            let now = Date()
            if lastLoggedProductionSpeed != mph || now.timeIntervalSince(lastProductionSpeedLogAt) >= 1.0 {
                lastLoggedProductionSpeed = mph
                lastProductionSpeedLogAt = now
                emit("MAP SPEED", "source=OBD value=\(mph)mph ecu=\(kmh)kmh gps=\(gps)mph hudOBD=\(hudAfter ? 1 : 0)", event: "production_speed", fields: ["mph": mph, "kmh": kmh, "gps_mph": gps, "hud_obd": hudAfter])
            }
        }

        // Drop consumed text so a duplicate notification cannot keep matching an
        // ancient response forever. Retain only a small tail for fragmented frames.
        streamBuffer = String(streamBuffer.suffix(64))
    }

    private func chooseCharacteristics(for peripheral: CBPeripheral) {
        let chars = peripheral.services?.flatMap { $0.characteristics ?? [] } ?? []
        let writable = chars.filter { $0.properties.contains(.writeWithoutResponse) || $0.properties.contains(.write) }
        let notifying = chars.filter { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }

        // The tested adapter exposes service FFF0 / characteristic FFF1. Keep the
        // generic selection fallback so other ELM BLE variants still work.
        txCharacteristic = writable.first(where: { $0.uuid.uuidString.uppercased() == "FFF1" })
            ?? writable.first(where: { $0.properties.contains(.notify) || $0.properties.contains(.indicate) })
            ?? writable.first
        rxCharacteristics = notifying
        if rxCharacteristics.isEmpty, let txCharacteristic, txCharacteristic.properties.contains(.read) {
            rxCharacteristics = [txCharacteristic]
        }
        for characteristic in notifying where !characteristic.isNotifying {
            peripheral.setNotifyValue(true, for: characteristic)
        }
        gattReady = txCharacteristic != nil && !rxCharacteristics.isEmpty
        txSummary = txCharacteristic.map { Self.characteristicDescription($0) } ?? "No writable characteristic"
        rxSummary = rxCharacteristics.isEmpty ? "No notify/indicate/read characteristic" : rxCharacteristics.map(Self.characteristicDescription).joined(separator: " | ")
        gattSummary = "services \(peripheral.services?.count ?? 0) • characteristics \(chars.count) • \(gattReady ? "speed-ready" : "incomplete")"
        emit("ELM GATT", "discovery complete \(gattSummary) TX={\(txSummary)} RX={\(rxSummary)}", event: "gatt_ready", fields: ["services": peripheral.services?.count ?? 0, "characteristics": chars.count, "ready": gattReady, "tx": txSummary, "rx": rxSummary])
        if gattReady { startPollingIfReady() }
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
                self.stopPolling(reason: "Bluetooth state \(central.state.rawValue)")
                self.status = "Bluetooth unavailable • state \(central.state.rawValue)"
            } else if self.mapModeOwnershipRequested && self.connectedPeripheral == nil {
                self.claimForMapMode()
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
            if let index = self.devices.firstIndex(where: { $0.id == device.id }) { self.devices[index] = device } else { self.devices.append(device) }
            self.devices.sort {
                let lhsOBD = $0.name.localizedCaseInsensitiveContains("OBD") || $0.name.localizedCaseInsensitiveContains("ELM")
                let rhsOBD = $1.name.localizedCaseInsensitiveContains("OBD") || $1.name.localizedCaseInsensitiveContains("ELM")
                if lhsOBD != rhsOBD { return lhsOBD && !rhsOBD }
                return $0.rssi > $1.rssi
            }
            let isOBD = name.localizedCaseInsensitiveContains("OBD") || name.localizedCaseInsensitiveContains("ELM") || services.contains(where: { $0.uppercased() == "FFF0" })
            if self.selectedDeviceID == nil && isOBD { self.selectedDeviceID = peripheral.identifier }
            self.emit("ELM SCAN", "FOUND name=\(name) id=\(peripheral.identifier) rssi=\(RSSI.intValue) connectable=\(connectable ? 1 : 0) services=[\(services.joined(separator: ","))] hudOBD=\((self.hudOBDConnectedProvider?() ?? false) ? 1 : 0)", event: "device_found", fields: ["name": name, "id": peripheral.identifier.uuidString, "rssi": RSSI.intValue, "connectable": connectable, "services": services])

            if self.autoConnectDiscoveredOBD && self.mapModeOwnershipRequested && isOBD && connectable && self.connectedPeripheral == nil && !self.connecting {
                self.selectedDeviceID = peripheral.identifier
                self.autoConnectDiscoveredOBD = false
                self.connect(peripheral, production: true)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            let productionGeneration = self.productionConnectGeneration.removeValue(forKey: peripheral.identifier)
            let staleProductionConnect = productionGeneration != nil && (!self.mapModeOwnershipRequested || productionGeneration != self.ownershipGeneration)
            if staleProductionConnect {
                if self.connectingPeripheral?.identifier == peripheral.identifier { self.connectingPeripheral = nil }
                self.connecting = false
                // Keep releaseCancellationPendingIDs populated until didDisconnect;
                // the physical BLE link did briefly complete, so the HUD must not
                // reclaim until cancellation is acknowledged (or the bounded
                // release barrier times out).
                self.releaseCancellationPendingIDs.insert(peripheral.identifier)
                self.emit(
                    "OBD OWNERSHIP",
                    "LATE CONNECT REJECTED device=\(peripheral.name ?? peripheral.identifier.uuidString) callbackGeneration=\(productionGeneration ?? 0) currentGeneration=\(self.ownershipGeneration) mapModeOwnership=\(self.mapModeOwnershipRequested ? 1 : 0); cancelling before GATT discovery",
                    event: "map_obd_late_connect_rejected",
                    fields: ["callback_generation": productionGeneration ?? 0, "current_generation": self.ownershipGeneration, "map_mode_ownership": self.mapModeOwnershipRequested]
                )
                central.cancelPeripheralConnection(peripheral)
                return
            }
            self.connecting = false
            if self.connectingPeripheral?.identifier == peripheral.identifier { self.connectingPeripheral = nil }
            self.connectedPeripheral = peripheral
            self.connectedName = peripheral.name ?? peripheral.identifier.uuidString
            self.status = "Connected • discovering GATT"
            peripheral.delegate = self
            if let name = self.connectedName,
               name.localizedCaseInsensitiveContains("OBD") || name.localizedCaseInsensitiveContains("ELM") {
                UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: self.savedPeripheralKey)
                UserDefaults.standard.set(name, forKey: self.savedNameKey)
                self.selectedDeviceID = peripheral.identifier
            }
            let hudAfter = self.hudOBDConnectedProvider?() ?? false
            self.emit("ELM CONN", "CONNECTED device=\(self.connectedName ?? "?") hudOBDBefore=\((self.hudOBDBeforeConnect ?? false) ? 1 : 0) hudOBDAfter=\(hudAfter ? 1 : 0) mapModeOwnership=\(self.mapModeOwnershipRequested ? 1 : 0)", event: "connected", fields: ["device": self.connectedName ?? "?", "hud_obd_before": self.hudOBDBeforeConnect ?? false, "hud_obd_after": hudAfter, "map_mode_ownership": self.mapModeOwnershipRequested])
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            let callbackGeneration = self.productionConnectGeneration.removeValue(forKey: peripheral.identifier)
            self.releaseCancellationPendingIDs.remove(peripheral.identifier)
            self.connecting = false
            if self.connectingPeripheral?.identifier == peripheral.identifier { self.connectingPeripheral = nil }
            self.status = "Connection failed"
            let belongsToCurrentOwnership = callbackGeneration == nil || callbackGeneration == self.ownershipGeneration
            if self.mapModeOwnershipRequested && belongsToCurrentOwnership {
                self.ownershipStatus = "OBD connection failed • GPS fallback"
                if !self.scanning { self.beginScan(duration: 6, productionAutoConnect: true) }
            }
            self.emit("ELM CONN", "FAILED device=\(peripheral.name ?? peripheral.identifier.uuidString) error=\(error?.localizedDescription ?? "unknown") hudOBD=\((self.hudOBDConnectedProvider?() ?? false) ? 1 : 0)", event: "connect_failed", fields: ["error": error?.localizedDescription ?? "unknown"])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.productionConnectGeneration.removeValue(forKey: peripheral.identifier)
            self.releaseCancellationPendingIDs.remove(peripheral.identifier)
            self.speedProbeTimeoutTask?.cancel(); self.speedProbeTimeoutTask = nil
            self.speedProbeActive = false
            self.stopPolling(reason: "BLE disconnected")
            self.connecting = false
            if self.connectingPeripheral?.identifier == peripheral.identifier { self.connectingPeripheral = nil }
            self.connectedPeripheral = nil
            self.connectedName = nil
            self.txCharacteristic = nil
            self.rxCharacteristics.removeAll()
            self.gattReady = false
            self.gattSummary = "—"
            self.status = "Disconnected"
            self.emit("ELM CONN", "DISCONNECTED device=\(peripheral.name ?? peripheral.identifier.uuidString) error=\(error?.localizedDescription ?? "none") hudOBD=\((self.hudOBDConnectedProvider?() ?? false) ? 1 : 0) mapModeOwnership=\(self.mapModeOwnershipRequested ? 1 : 0)", event: "disconnected", fields: ["error": error?.localizedDescription ?? "none"])
            if self.mapModeOwnershipRequested {
                self.ownershipStatus = "OBD disconnected • GPS fallback"
                self.beginScan(duration: 6, productionAutoConnect: true)
            } else {
                self.ownershipStatus = "HUD may reclaim OBD"
            }
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
            // Production polling can be 5 Hz. Keep raw RX in the structured diagnostic
            // recorder but avoid flooding the human HUD log with every echo/fragment.
            if !self.productionPolling || ascii.uppercased().contains("41 0D") {
                self.emit("ELM RX", "char=\(characteristic.uuid.uuidString) bytes=\(data.count) ascii={\(self.lastRX)} hex={\(hex)}", event: "rx", fields: ["characteristic": characteristic.uuid.uuidString, "bytes": data.count, "ascii": ascii, "hex": hex])
            } else {
                self.diagnostics.record("elm327", "rx_poll_fragment", fields: ["characteristic": characteristic.uuid.uuidString, "bytes": data.count, "ascii": ascii, "hex": hex])
            }
            if !ascii.isEmpty { self.considerSpeedResponse(ascii) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if error != nil || !self.productionPolling {
                self.emit("ELM TX", "write callback char=\(characteristic.uuid.uuidString) error=\(error?.localizedDescription ?? "none")", event: "write_callback", fields: ["error": error?.localizedDescription ?? "none"])
            }
        }
    }
}

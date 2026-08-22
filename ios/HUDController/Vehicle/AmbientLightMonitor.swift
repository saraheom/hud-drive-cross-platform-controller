import Foundation
import CoreBluetooth
import Observation

/// v89 expands the original BLEDOM presence monitor into a multi-device ambient
/// lighting controller while preserving the HUD Auto Brightness trigger path.
///
/// One CBCentralManager owns all ambient-light BLE work so the controller UI and
/// the legacy BLEDOM presence detector never compete for the same peripheral.
@MainActor
@Observable
final class AmbientLightMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // MARK: - Legacy HUD auto-brightness state (kept source/API compatible)

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

    /// Independent from the ambient-controller master switch. This preserves
    /// the existing ELK-BLEDOM presence behavior without forcing direct light
    /// control users to enable HUD Auto Brightness.
    var hudBrightnessTriggerEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hudBrightnessTriggerEnabled, forKey: "HUD.Ambient.hudBrightnessTrigger")
            if !hudBrightnessTriggerEnabled {
                lightPresent = false
                if bluetooth.state == .connected {
                    bluetooth.enqueue(
                        HudCommands.autoBrightness(false),
                        label: "Ambient trigger disabled → Auto brightness OFF"
                    )
                }
            } else if enabled {
                startScanning()
            }
        }
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

    // MARK: - v89 controller state

    private(set) var discoveredDevices: [AmbientDiscoveredDevice] = []
    private(set) var pairedDevices: [AmbientLightDevice]
    private(set) var groups: [AmbientLightGroup]
    private(set) var controllerStatus = "Ambient lighting disabled"

    private var central: CBCentralManager!
    private let bluetooth: HudBluetoothManager
    private let logger: LogManager

    /// The single peripheral whose presence controls the physical HUD's Auto
    /// Brightness setting. Other paired ambient lights do not affect it.
    private var trackedPeripheral: CBPeripheral?
    private var lastSeen = Date.distantPast
    private var watchdogTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var connectionAttemptStartedAt: Date?
    private var isScanning = false
    private var lastHUDReassertAt = Date.distantPast
    private let absenceConfirmationWindows = 3

    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var lastSeenByID: [UUID: Date] = [:]
    private var rssiByID: [UUID: Int] = [:]
    private var connectionStartedByID: [UUID: Date] = [:]
    private var serviceUUIDsByID: [UUID: Set<String>] = [:]
    private var characteristicUUIDsByID: [UUID: Set<String>] = [:]
    private var writeCharacteristicsByID: [UUID: CBCharacteristic] = [:]
    private var animationTasks: [UUID: Task<Void, Never>] = [:]
    private var animatedConnectionSession: Set<UUID> = []
    private var sessionResetTasks: [UUID: Task<Void, Never>] = [:]

    private let peripheralIDKey = "HUD.Ambient.peripheralUUID"
    private let pairedDevicesKey = "HUD.Ambient.v89.pairedDevices"
    private let groupsKey = "HUD.Ambient.v89.groups"

    init(bluetooth: HudBluetoothManager, logger: LogManager) {
        self.bluetooth = bluetooth
        self.logger = logger

        let d = UserDefaults.standard
        let legacyEnabled = d.object(forKey: "HUD.Ambient.enabled") == nil
            ? false : d.bool(forKey: "HUD.Ambient.enabled")
        self.enabled = legacyEnabled
        self.targetName = d.string(forKey: "HUD.Ambient.targetName") ?? "BLEDOM"
        self.hudBrightnessTriggerEnabled = d.object(forKey: "HUD.Ambient.hudBrightnessTrigger") == nil
            ? legacyEnabled : d.bool(forKey: "HUD.Ambient.hudBrightnessTrigger")
        self.absenceTimeoutSeconds = d.object(forKey: "HUD.Ambient.timeout") == nil
            ? 5 : Self.clampedTimeout(d.integer(forKey: "HUD.Ambient.timeout"))
        self.pairedDevices = Self.decode([AmbientLightDevice].self, key: "HUD.Ambient.v89.pairedDevices") ?? []
        self.groups = Self.decode([AmbientLightGroup].self, key: "HUD.Ambient.v89.groups") ?? []

        super.init()

        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "HUDAmbientCentral.v45"]
        )

        migrateLegacyBLEDOMPairingIfNeeded()
    }

    // MARK: - Persistence

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func persistPairedDevices() {
        if let data = try? JSONEncoder().encode(pairedDevices) {
            UserDefaults.standard.set(data, forKey: pairedDevicesKey)
        }
    }

    private func persistGroups() {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: groupsKey)
        }
    }

    /// Existing v88 users already have the ELK-BLEDOM CoreBluetooth UUID saved.
    /// Promote that remembered light into the new controller once, without
    /// changing its role as the HUD Auto Brightness presence trigger.
    private func migrateLegacyBLEDOMPairingIfNeeded() {
        guard pairedDevices.isEmpty,
              let raw = UserDefaults.standard.string(forKey: peripheralIDKey),
              let id = UUID(uuidString: raw) else { return }

        pairedDevices.append(
            AmbientLightDevice(
                id: id,
                customName: "BLEDOM Ambient",
                advertisedName: targetName,
                protocolKind: .lotusLantern,
                autoConnect: true
            )
        )
        persistPairedDevices()
        logger.log("AMBIENT CTRL", "Migrated remembered BLEDOM \(id) into v89 ambient controller")
    }

    // MARK: - Start / stop / discovery

    func start() {
        guard central.state == .poweredOn else {
            status = "Waiting for Bluetooth"
            controllerStatus = "Waiting for Bluetooth"
            return
        }

        restoreRememberedPeripheralIfPossible()
        restorePairedPeripheralsIfPossible()

        // Always scan from startup, even when a remembered peripheral exists.
        // A remembered CoreBluetooth connection can otherwise sit in
        // `.connecting` for minutes with no advertisement fallback.
        startScanning()

        if let trackedPeripheral {
            maintainConnection(to: trackedPeripheral, reason: "start")
        }
        maintainPairedConnections(reason: "start")

        startWatchdog()
        controllerStatus = "Scanning for ambient lights"
    }

    func stop() {
        central.stopScan()
        isScanning = false
        watchdogTask?.cancel()
        watchdogTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil

        animationTasks.values.forEach { $0.cancel() }
        animationTasks.removeAll()
        sessionResetTasks.values.forEach { $0.cancel() }
        sessionResetTasks.removeAll()

        var idsToDisconnect = Set(pairedDevices.map(\.id))
        if let trackedPeripheral { idsToDisconnect.insert(trackedPeripheral.identifier) }
        for id in idsToDisconnect {
            guard let peripheral = peripheralsByID[id] ?? (trackedPeripheral?.identifier == id ? trackedPeripheral : nil)
            else { continue }
            if peripheral.state == .connected || peripheral.state == .connecting {
                central.cancelPeripheralConnection(peripheral)
            }
        }

        status = "Stopped"
        controllerStatus = "Ambient lighting disabled"
    }

    func scanNow() {
        guard enabled else {
            controllerStatus = "Enable Ambient Lighting first"
            return
        }
        discoveredDevices.removeAll()
        if isScanning {
            central.stopScan()
            isScanning = false
        }
        startScanning()
    }

    private func startScanning() {
        guard enabled,
              central.state == .poweredOn else { return }

        // CBCentralManager.scanForPeripherals is already continuous. Reissuing
        // it every 500 ms adds needless CoreBluetooth/log churn and can
        // destabilize a long-running drive session.
        guard !isScanning else { return }

        isScanning = true
        central.scanForPeripherals(
            withServices: nil,
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ]
        )
        logger.log(
            "AMBIENT BG",
            "Started BLE advertisement scan for BLEDOM"
        )
    }

    private func restoreRememberedPeripheralIfPossible() {
        guard trackedPeripheral == nil,
              let raw = UserDefaults.standard.string(forKey: peripheralIDKey),
              let uuid = UUID(uuidString: raw) else { return }

        if let peripheral = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            trackedPeripheral = peripheral
            peripheralsByID[uuid] = peripheral
            peripheral.delegate = self
            detectedIdentifier = peripheral.identifier.uuidString
            detectedName = peripheral.name ?? targetName
            logger.log(
                "AMBIENT BG",
                "Retrieved remembered \(detectedName) \(detectedIdentifier)"
            )
        }
    }

    private func restorePairedPeripheralsIfPossible() {
        let ids = pairedDevices.map(\.id)
        guard !ids.isEmpty else { return }
        for peripheral in central.retrievePeripherals(withIdentifiers: ids) {
            peripheralsByID[peripheral.identifier] = peripheral
            peripheral.delegate = self
        }
    }

    // MARK: - Pairing + grouping API

    func inferredProtocol(for discovered: AmbientDiscoveredDevice) -> AmbientLightProtocolKind {
        let upper = discovered.advertisedName.uppercased()
        if upper.contains("BLEDOM") || upper.hasPrefix("ELK-") || upper.hasPrefix("ELK~") || upper.contains("LED LIGHT STRIP") {
            return .lotusLantern
        }
        // The user's two BLEDIM2-compatible units do not expose a useful name.
        return .bledim2
    }

    func pair(_ discovered: AmbientDiscoveredDevice, as protocolKind: AmbientLightProtocolKind? = nil) {
        guard pairedDevices.first(where: { $0.id == discovered.id }) == nil else { return }
        let kind = protocolKind ?? inferredProtocol(for: discovered)
        let custom = discovered.advertisedName.isEmpty
            ? "Ambient Light \(discovered.id.uuidString.suffix(4))"
            : discovered.advertisedName

        pairedDevices.append(
            AmbientLightDevice(
                id: discovered.id,
                customName: custom,
                advertisedName: discovered.advertisedName,
                protocolKind: kind
            )
        )
        persistPairedDevices()
        logger.log("AMBIENT CTRL", "Paired \(custom) \(discovered.id) protocol=\(kind.rawValue)")

        if let peripheral = peripheralsByID[discovered.id] {
            maintainConnection(to: peripheral, reason: "newly paired")
        }
    }

    func unpair(_ id: UUID) {
        let name = pairedDevice(id)?.displayName ?? id.uuidString
        pairedDevices.removeAll { $0.id == id }
        for index in groups.indices {
            groups[index].memberIDs.removeAll { $0 == id }
        }
        persistPairedDevices()
        persistGroups()
        animationTasks[id]?.cancel()
        animationTasks[id] = nil
        writeCharacteristicsByID[id] = nil

        // Do not disconnect the legacy BLEDOM if it is still the HUD brightness
        // trigger. Unpairing only removes direct color-control ownership.
        if trackedPeripheral?.identifier != id,
           let peripheral = peripheralsByID[id],
           peripheral.state == .connected || peripheral.state == .connecting {
            central.cancelPeripheralConnection(peripheral)
        }
        logger.log("AMBIENT CTRL", "Unpaired \(name)")
    }

    func pairedDevice(_ id: UUID) -> AmbientLightDevice? {
        pairedDevices.first { $0.id == id }
    }

    func renameDevice(_ id: UUID, to name: String) {
        updateDevice(id) { $0.customName = name }
    }

    func setProtocol(_ id: UUID, to kind: AmbientLightProtocolKind) {
        updateDevice(id) { $0.protocolKind = kind }
        writeCharacteristicsByID[id] = nil
        if let peripheral = peripheralsByID[id], peripheral.state == .connected {
            peripheral.discoverServices(nil)
        }
    }

    func setAutoConnect(_ id: UUID, enabled: Bool) {
        updateDevice(id) { $0.autoConnect = enabled }
        if enabled, let peripheral = peripheralsByID[id] {
            maintainConnection(to: peripheral, reason: "auto-connect enabled")
        }
    }

    func createGroup(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        groups.append(AmbientLightGroup(name: trimmed))
        persistGroups()
    }

    func renameGroup(_ id: UUID, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
        persistGroups()
    }

    func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        persistGroups()
    }

    func setGroupMembership(groupID: UUID, deviceID: UUID, included: Bool) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        var members = groups[index].memberIDs
        if included {
            if !members.contains(deviceID) { members.append(deviceID) }
        } else {
            members.removeAll { $0 == deviceID }
        }
        groups[index].memberIDs = members
        persistGroups()
    }

    func group(_ id: UUID) -> AmbientLightGroup? {
        groups.first { $0.id == id }
    }

    // MARK: - Runtime UI helpers

    func isConnected(_ id: UUID) -> Bool {
        peripheralsByID[id]?.state == .connected
    }

    func isControllable(_ id: UUID) -> Bool {
        guard let device = pairedDevice(id), device.protocolKind == .lotusLantern else { return false }
        guard !isEncryptedLotusName(device.advertisedName) else { return false }
        return isConnected(id) && writeCharacteristicsByID[id] != nil
    }

    func connectionLabel(_ id: UUID) -> String {
        guard let device = pairedDevice(id) else { return "Unknown" }
        let state: String
        switch peripheralsByID[id]?.state {
        case .connected?: state = "Connected"
        case .connecting?: state = "Connecting…"
        case .disconnecting?: state = "Disconnecting…"
        default: state = "Disconnected"
        }

        if state == "Connected" && device.protocolKind == .bledim2 {
            return "Connected • GATT diagnostics"
        }
        if state == "Connected" && device.protocolKind == .lotusLantern && writeCharacteristicsByID[id] == nil {
            return "Connected • discovering control characteristic"
        }
        return state
    }

    func rssi(_ id: UUID) -> Int? { rssiByID[id] }

    func gattSummary(_ id: UUID) -> String {
        let services = (serviceUUIDsByID[id] ?? []).sorted()
        let characteristics = (characteristicUUIDsByID[id] ?? []).sorted()
        if services.isEmpty && characteristics.isEmpty { return "No GATT fingerprint yet" }
        let s = services.isEmpty ? "—" : services.joined(separator: ", ")
        let c = characteristics.isEmpty ? "—" : characteristics.joined(separator: ", ")
        return "Services: \(s)\nCharacteristics: \(c)"
    }

    // MARK: - Device state / commands

    func setPower(_ id: UUID, on: Bool) {
        animationTasks[id]?.cancel()
        animationTasks[id] = nil
        updateDevice(id) { $0.powerOn = on }
        sendPower(id, on: on, reason: "manual")
    }

    func setColor(_ id: UUID, color: AmbientRGB) {
        animationTasks[id]?.cancel()
        animationTasks[id] = nil
        updateDevice(id) { $0.color = color }
        sendColor(id, color: color, reason: "manual")
    }

    func setBrightness(_ id: UUID, percent: Int) {
        animationTasks[id]?.cancel()
        animationTasks[id] = nil
        let clamped = max(0, min(100, percent))
        updateDevice(id) { $0.brightness = clamped }
        sendBrightness(id, percent: clamped, reason: "manual")
    }

    func setStartupAnimationEnabled(_ id: UUID, enabled: Bool) {
        updateDevice(id) { $0.startupAnimationEnabled = enabled }
    }

    func setStartupCycles(_ id: UUID, cycles: Int) {
        updateDevice(id) { $0.startupCycles = max(1, min(2, cycles)) }
    }

    func setStartupDuration(_ id: UUID, seconds: Double) {
        updateDevice(id) { $0.startupDurationSeconds = max(0.4, min(5.0, seconds)) }
    }

    func previewStartupAnimation(_ id: UUID) {
        animatedConnectionSession.remove(id)
        runStartupAnimationIfNeeded(id, force: true)
    }

    func setGroupPower(_ groupID: UUID, on: Bool) {
        guard let group = group(groupID) else { return }
        for id in group.memberIDs { setPower(id, on: on) }
    }

    func setGroupColor(_ groupID: UUID, color: AmbientRGB) {
        guard let group = group(groupID) else { return }
        for id in group.memberIDs { setColor(id, color: color) }
    }

    func setGroupBrightness(_ groupID: UUID, percent: Int) {
        guard let group = group(groupID) else { return }
        for id in group.memberIDs { setBrightness(id, percent: percent) }
    }

    private func updateDevice(_ id: UUID, mutation: (inout AmbientLightDevice) -> Void) {
        guard let index = pairedDevices.firstIndex(where: { $0.id == id }) else { return }
        mutation(&pairedDevices[index])
        persistPairedDevices()
    }

    // MARK: - Packet adapters

    private func sendPower(_ id: UUID, on: Bool, reason: String) {
        guard let device = pairedDevice(id) else { return }
        switch device.protocolKind {
        case .lotusLantern:
            writeLotus(LotusLanternProtocol.power(on), to: id, label: "power \(on ? "ON" : "OFF") \(reason)")
        case .bledim2:
            logBLEDIM2Unsupported(device, command: "power")
        }
    }

    private func sendColor(_ id: UUID, color: AmbientRGB, reason: String) {
        guard let device = pairedDevice(id) else { return }
        switch device.protocolKind {
        case .lotusLantern:
            writeLotus(LotusLanternProtocol.color(color), to: id, label: "RGB \(color.red),\(color.green),\(color.blue) \(reason)")
        case .bledim2:
            logBLEDIM2Unsupported(device, command: "RGB")
        }
    }

    private func sendBrightness(_ id: UUID, percent: Int, reason: String) {
        guard let device = pairedDevice(id) else { return }
        switch device.protocolKind {
        case .lotusLantern:
            writeLotus(LotusLanternProtocol.brightness(percent), to: id, label: "brightness \(percent)% \(reason)")
        case .bledim2:
            logBLEDIM2Unsupported(device, command: "brightness")
        }
    }

    private func writeLotus(_ data: Data, to id: UUID, label: String) {
        guard let device = pairedDevice(id) else { return }
        guard !isEncryptedLotusName(device.advertisedName) else {
            logger.log("AMBIENT CTRL", "Blocked encrypted ELK-* write for \(device.displayName); encrypted dialect is not enabled")
            return
        }
        guard let peripheral = peripheralsByID[id], peripheral.state == .connected,
              let characteristic = writeCharacteristicsByID[id] else {
            logger.log("AMBIENT CTRL", "Cannot send \(label) to \(device.displayName): control characteristic unavailable")
            return
        }

        let writeType: CBCharacteristicWriteType
        // LED controllers are often optimized for write-without-response. Use
        // it when advertised so fades do not build a response queue; fall back
        // to acknowledged writes on controllers that require them.
        if characteristic.properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else if characteristic.properties.contains(.write) {
            writeType = .withResponse
        } else {
            logger.log("AMBIENT CTRL", "FFF3 is not writable for \(device.displayName)")
            return
        }

        peripheral.writeValue(data, for: characteristic, type: writeType)
        logger.log("AMBIENT TX", "\(device.displayName) \(label): \(Self.hex(data))")
    }

    private func logBLEDIM2Unsupported(_ device: AmbientLightDevice, command: String) {
        logger.log(
            "AMBIENT BLEDIM2",
            "Deferred \(command) for \(device.displayName): supplied BLEDIM2 1.960 APK is packed; capture exact write protocol first"
        )
        controllerStatus = "BLEDIM2 connected for diagnostics; write protocol capture still needed"
    }

    private func isEncryptedLotusName(_ name: String) -> Bool {
        // Lotus Lantern 6.5.08 only selects its encrypted branch when the
        // advertised name literally contains the marker \"ELK-*\". Ordinary
        // ELK-BLEDOM devices use the recovered 7E...EF packet family.
        name.uppercased().contains("ELK-*")
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    // MARK: - Startup animation

    private func restoreDeviceState(_ id: UUID) {
        guard let device = pairedDevice(id), device.protocolKind == .lotusLantern else { return }
        sendColor(id, color: device.color, reason: "restore")
        sendBrightness(id, percent: device.brightness, reason: "restore")
        sendPower(id, on: device.powerOn, reason: "restore")
    }

    private func runStartupAnimationIfNeeded(_ id: UUID, force: Bool = false) {
        guard let device = pairedDevice(id),
              device.protocolKind == .lotusLantern,
              isControllable(id) else { return }

        if !force && animatedConnectionSession.contains(id) {
            restoreDeviceState(id)
            return
        }

        guard device.startupAnimationEnabled, device.powerOn else {
            animatedConnectionSession.insert(id)
            restoreDeviceState(id)
            return
        }

        animationTasks[id]?.cancel()
        animatedConnectionSession.insert(id)

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let steps = 12
            let cycles = max(1, min(2, device.startupCycles))
            let target = max(1, min(100, device.brightness))
            let fadeSeconds = max(0.2, device.startupDurationSeconds / 2.0)
            let stepNanoseconds = UInt64((fadeSeconds / Double(steps)) * 1_000_000_000)

            self.logger.log(
                "AMBIENT ANIM",
                "Startup animation begin \(device.displayName) cycles=\(cycles) target=\(target)%"
            )
            self.sendColor(id, color: device.color, reason: "startup")
            self.sendPower(id, on: true, reason: "startup")
            self.sendBrightness(id, percent: 0, reason: "startup")

            func fade(from: Int, to: Int) async -> Bool {
                for step in 1...steps {
                    guard !Task.isCancelled else { return false }
                    let fraction = Double(step) / Double(steps)
                    let value = Int((Double(from) + (Double(to - from) * fraction)).rounded())
                    self.sendBrightness(id, percent: value, reason: "startup fade")
                    try? await Task.sleep(nanoseconds: stepNanoseconds)
                }
                return !Task.isCancelled
            }

            for _ in 0..<cycles {
                guard await fade(from: 0, to: target) else { return }
                guard await fade(from: target, to: 0) else { return }
            }
            guard await fade(from: 0, to: target) else { return }

            self.sendColor(id, color: device.color, reason: "startup final")
            self.sendBrightness(id, percent: target, reason: "startup final")
            self.sendPower(id, on: true, reason: "startup final")
            self.logger.log("AMBIENT ANIM", "Startup animation complete \(device.displayName)")
            self.animationTasks[id] = nil
        }
        animationTasks[id] = task
    }

    /// Do not replay the startup pulse for a momentary BLE dropout. A device
    /// must remain disconnected for 15 seconds before the next connection is
    /// treated as a fresh ambient-light power session.
    private func scheduleStartupSessionReset(_ id: UUID) {
        sessionResetTasks[id]?.cancel()
        sessionResetTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            if self.peripheralsByID[id]?.state != .connected {
                self.animatedConnectionSession.remove(id)
                self.logger.log("AMBIENT ANIM", "Startup session reset after 15s disconnect for \(id)")
            }
            self.sessionResetTasks[id] = nil
        }
    }

    // MARK: - Connection management

    private func maintainConnection(to peripheral: CBPeripheral, reason: String) {
        guard enabled, central.state == .poweredOn else { return }

        peripheralsByID[peripheral.identifier] = peripheral
        peripheral.delegate = self

        switch peripheral.state {
        case .connected:
            if trackedPeripheral?.identifier == peripheral.identifier {
                markPresent(
                    name: peripheral.name ?? detectedName,
                    identifier: peripheral.identifier.uuidString,
                    rssi: lastRSSI,
                    reason: "persistent GATT connection"
                )
            }
            if pairedDevice(peripheral.identifier) != nil {
                peripheral.discoverServices(nil)
            }
        case .connecting:
            if trackedPeripheral?.identifier == peripheral.identifier {
                status = "\(peripheral.name ?? targetName) connecting…"
            }
        case .disconnected, .disconnecting:
            if peripheral.state == .disconnecting { return }
            if trackedPeripheral?.identifier == peripheral.identifier {
                status = "\(peripheral.name ?? targetName) background watch connecting…"
                connectionAttemptStartedAt = Date()
            }
            connectionStartedByID[peripheral.identifier] = Date()
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

    private func maintainPairedConnections(reason: String) {
        for device in pairedDevices where device.autoConnect {
            if let peripheral = peripheralsByID[device.id] {
                maintainConnection(to: peripheral, reason: "paired \(reason)")
            }
        }
    }

    // MARK: - Legacy HUD brightness presence behavior

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
        guard enabled, hudBrightnessTriggerEnabled, bluetooth.state == .connected else { return }

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

    // MARK: - CBCentralManagerDelegate

    nonisolated func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String : Any]
    ) {
        Task { @MainActor in
            self.logger.log("AMBIENT BG", "CoreBluetooth restored ambient central state")

            if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
                for peripheral in peripherals {
                    self.peripheralsByID[peripheral.identifier] = peripheral
                    peripheral.delegate = self
                }

                if let raw = UserDefaults.standard.string(forKey: self.peripheralIDKey),
                   let rememberedID = UUID(uuidString: raw),
                   let remembered = peripherals.first(where: { $0.identifier == rememberedID }) {
                    self.trackedPeripheral = remembered
                    self.detectedIdentifier = remembered.identifier.uuidString
                    self.detectedName = remembered.name ?? self.targetName
                }
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
            } else if central.state != .poweredOn {
                self.controllerStatus = "Bluetooth unavailable"
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
            let name = localName ?? peripheral.name ?? ""
            let id = peripheral.identifier
            let advertisedServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
                .map { $0.uuidString.uppercased() }

            self.peripheralsByID[id] = peripheral
            peripheral.delegate = self
            self.lastSeenByID[id] = Date()
            self.rssiByID[id] = RSSI.intValue
            self.upsertDiscovered(
                id: id,
                name: name,
                rssi: RSSI.intValue,
                serviceUUIDs: advertisedServices
            )

            let matchesBrightnessTarget = self.hudBrightnessTriggerEnabled &&
                !self.targetName.isEmpty &&
                name.localizedCaseInsensitiveContains(self.targetName)

            if matchesBrightnessTarget {
                self.trackedPeripheral = peripheral
                UserDefaults.standard.set(id.uuidString, forKey: self.peripheralIDKey)
                self.markPresent(
                    name: name.isEmpty ? self.targetName : name,
                    identifier: id.uuidString,
                    rssi: RSSI.intValue,
                    reason: "advertisement"
                )
                self.maintainConnection(to: peripheral, reason: "matched advertisement")
            }

            if let device = self.pairedDevice(id), device.autoConnect {
                self.maintainConnection(to: peripheral, reason: "paired advertisement")
            }
        }
    }

    private func upsertDiscovered(id: UUID, name: String, rssi: Int, serviceUUIDs: [String]) {
        if let index = discoveredDevices.firstIndex(where: { $0.id == id }) {
            discoveredDevices[index].advertisedName = name.isEmpty
                ? discoveredDevices[index].advertisedName : name
            discoveredDevices[index].rssi = rssi
            if !serviceUUIDs.isEmpty { discoveredDevices[index].serviceUUIDs = serviceUUIDs }
            discoveredDevices[index].lastSeen = Date()
        } else {
            discoveredDevices.append(
                AmbientDiscoveredDevice(
                    id: id,
                    advertisedName: name,
                    rssi: rssi,
                    serviceUUIDs: serviceUUIDs,
                    lastSeen: Date()
                )
            )
        }

        // Keep the scanner useful in a busy parking lot without allowing an
        // unbounded observed array. Strongest RSSI devices stay visible first.
        discoveredDevices.sort { $0.rssi > $1.rssi }
        if discoveredDevices.count > 40 {
            discoveredDevices.removeLast(discoveredDevices.count - 40)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        Task { @MainActor in
            let id = peripheral.identifier
            self.peripheralsByID[id] = peripheral
            peripheral.delegate = self
            self.connectionStartedByID[id] = nil
            self.sessionResetTasks[id]?.cancel()
            self.sessionResetTasks[id] = nil

            if self.trackedPeripheral?.identifier == id {
                UserDefaults.standard.set(id.uuidString, forKey: self.peripheralIDKey)
                self.markPresent(
                    name: peripheral.name ?? self.targetName,
                    identifier: id.uuidString,
                    rssi: self.rssiByID[id] ?? self.lastRSSI,
                    reason: "CoreBluetooth didConnect"
                )
                self.connectionAttemptStartedAt = nil
                self.logger.log(
                    "AMBIENT BG",
                    "Persistent ambient BLE connection established; hybrid discovery remains armed"
                )
            }

            if self.pairedDevice(id) != nil {
                self.controllerStatus = "Connected to ambient light; discovering GATT"
                peripheral.discoverServices(nil)
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            let id = peripheral.identifier
            self.connectionStartedByID[id] = nil
            if self.trackedPeripheral?.identifier == id {
                self.connectionAttemptStartedAt = nil
            }
            self.logger.log(
                "AMBIENT BG",
                "Ambient connection failed \(id): \(error?.localizedDescription ?? "unknown")"
            )
            self.startScanning()
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
            let id = peripheral.identifier
            self.connectionStartedByID[id] = nil
            self.writeCharacteristicsByID[id] = nil
            self.animationTasks[id]?.cancel()
            self.animationTasks[id] = nil

            if self.trackedPeripheral?.identifier == id {
                self.connectionAttemptStartedAt = nil
            }

            self.logger.log(
                "AMBIENT BG",
                "Ambient peripheral disconnected \(id): \(error?.localizedDescription ?? "device unavailable")"
            )

            if self.trackedPeripheral?.identifier == id {
                // A GATT disconnect is an OS-delivered event and therefore remains
                // useful when the app is backgrounded/locked. Turn brightness OFF,
                // then leave another pending connect request so device power-on
                // automatically wakes/reconnects us.
                self.markAbsent(reason: "persistent BLE disconnect")
            }

            // Hybrid recovery: leave a GATT connection pending AND scan for
            // the remembered BLEDOM advertisement. If iOS delivers an
            // advertisement before GATT finishes, brightness turns ON
            // immediately rather than waiting ~10 seconds for didConnect.
            self.startScanning()
            self.scheduleConnectionRetry()
            self.scheduleStartupSessionReset(id)
        }
    }

    // MARK: - CBPeripheralDelegate / GATT fingerprinting

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            let id = peripheral.identifier
            if let error {
                self.logger.log("AMBIENT GATT", "Service discovery failed \(id): \(error.localizedDescription)")
                return
            }
            let services = peripheral.services ?? []
            var set = self.serviceUUIDsByID[id] ?? []
            for service in services {
                set.insert(service.uuid.uuidString.uppercased())
                peripheral.discoverCharacteristics(nil, for: service)
            }
            self.serviceUUIDsByID[id] = set
            self.logger.log("AMBIENT GATT", "\(id) services=\(set.sorted().joined(separator: ","))")
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            let id = peripheral.identifier
            if let error {
                self.logger.log("AMBIENT GATT", "Characteristic discovery failed \(id): \(error.localizedDescription)")
                return
            }

            var set = self.characteristicUUIDsByID[id] ?? []
            var newlyReady = false
            for characteristic in service.characteristics ?? [] {
                let uuid = characteristic.uuid.uuidString.uppercased()
                set.insert(uuid)
                let properties = self.propertyDescription(characteristic.properties)
                self.logger.log(
                    "AMBIENT GATT",
                    "\(id) service=\(service.uuid.uuidString) char=\(uuid) props=\(properties)"
                )

                if let device = self.pairedDevice(id),
                   device.protocolKind == .lotusLantern,
                   self.isLotusService(service.uuid),
                   self.isLotusWriteCharacteristic(characteristic.uuid),
                   characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                    if self.writeCharacteristicsByID[id] == nil { newlyReady = true }
                    self.writeCharacteristicsByID[id] = characteristic
                }
            }
            self.characteristicUUIDsByID[id] = set

            if let device = self.pairedDevice(id), device.protocolKind == .bledim2 {
                self.controllerStatus = "BLEDIM2 GATT fingerprint captured — export HUD log for protocol work"
            }

            if newlyReady, let device = self.pairedDevice(id) {
                self.controllerStatus = "\(device.displayName) ready"
                self.logger.log(
                    "AMBIENT CTRL",
                    "Lotus Lantern FFF0/FFF3 control ready for \(device.displayName)"
                )
                self.runStartupAnimationIfNeeded(id)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor in
            self.logger.log(
                "AMBIENT TX",
                "Write failed \(peripheral.identifier) char=\(characteristic.uuid.uuidString): \(error.localizedDescription)"
            )
        }
    }

    private func isLotusService(_ uuid: CBUUID) -> Bool {
        let value = uuid.uuidString.uppercased()
        return value == "FFF0" || value == LotusLanternProtocol.serviceUUID.uppercased()
    }

    private func isLotusWriteCharacteristic(_ uuid: CBUUID) -> Bool {
        let value = uuid.uuidString.uppercased()
        return value == "FFF3" || value == LotusLanternProtocol.writeCharacteristicUUID.uppercased()
    }

    private func propertyDescription(_ properties: CBCharacteristicProperties) -> String {
        var values: [String] = []
        if properties.contains(.read) { values.append("read") }
        if properties.contains(.write) { values.append("write") }
        if properties.contains(.writeWithoutResponse) { values.append("writeWithoutResponse") }
        if properties.contains(.notify) { values.append("notify") }
        if properties.contains(.indicate) { values.append("indicate") }
        return values.isEmpty ? "0x\(String(properties.rawValue, radix: 16))" : values.joined(separator: "+")
    }

    // MARK: - Retry / watchdog

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
            self.maintainPairedConnections(reason: "automatic retry")
        }
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            var pairedReconnectTick = 0
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

                // Apply the same six-second stall guard to every paired light.
                for (id, started) in self.connectionStartedByID {
                    guard Date().timeIntervalSince(started) > 6,
                          let peripheral = self.peripheralsByID[id],
                          peripheral.state == .connecting else { continue }
                    self.logger.log("AMBIENT BG", "Paired light connection stuck >6s \(id); retrying")
                    self.central.cancelPeripheralConnection(peripheral)
                    self.connectionStartedByID[id] = nil
                }

                if self.trackedPeripheral?.state != .connected {
                    self.startScanning()
                }

                pairedReconnectTick += 1
                if pairedReconnectTick >= 4 { // every ~2 seconds
                    pairedReconnectTick = 0
                    self.maintainPairedConnections(reason: "watchdog")
                }

                let connected = self.trackedPeripheral?.state == .connected
                let elapsed = Date().timeIntervalSince(self.lastSeen)
                let timeout = Double(max(1, self.absenceTimeoutSeconds))
                let missedWindows = Int(elapsed / timeout)

                if self.hudBrightnessTriggerEnabled && self.lightPresent && !connected &&
                    missedWindows >= self.absenceConfirmationWindows {
                    self.markAbsent(
                        reason: "\(self.absenceConfirmationWindows) missed advertisement windows"
                    )
                }

                if self.hudBrightnessTriggerEnabled && self.lightPresent,
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

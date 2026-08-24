import Foundation
import CoreBluetooth
import Observation

/// v90.5 expands the original BLEDOM presence monitor into a multi-device ambient
/// lighting controller, verified Lotus control, BLEDIM2 FFF1 protocol diagnostics,
/// vehicle-power choreography, and automatic Door day/night brightness management
/// while preserving the HUD Auto Brightness trigger path.
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

    // MARK: - v90 vehicle-aware automation

    var vehicleAutomationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(vehicleAutomationEnabled, forKey: "HUD.Ambient.v90.vehicleAutomation")
            if vehicleAutomationEnabled {
                evaluateVehicleLightingAutomation()
            } else {
                resetVehicleAutomationRuntime(reason: "automation disabled")
            }
        }
    }

    var vehicleStartupCycles: Int {
        didSet { UserDefaults.standard.set(max(1, min(2, vehicleStartupCycles)), forKey: "HUD.Ambient.v90.startupCycles") }
    }
    var vehicleStartupPulseDurationSeconds: Double {
        didSet { UserDefaults.standard.set(max(0.4, min(6.0, vehicleStartupPulseDurationSeconds)), forKey: "HUD.Ambient.v90.startupDuration") }
    }
    var startupClassificationSeconds: Double {
        didSet { UserDefaults.standard.set(max(1.0, min(8.0, startupClassificationSeconds)), forKey: "HUD.Ambient.v90.classification") }
    }
    var headlightJoinFadeSeconds: Double {
        didSet { UserDefaults.standard.set(max(0.4, min(6.0, headlightJoinFadeSeconds)), forKey: "HUD.Ambient.v90.headlightFade") }
    }

    /// v90.3: the door controller is powered for the entire engine session, so its
    /// steady-state brightness can be independently tuned for daylight and night.
    /// These targets are vehicle-automation settings and intentionally do not
    /// overwrite the device's generic/manual preferred brightness.
    var doorDayBrightness: Int {
        didSet { UserDefaults.standard.set(max(0, min(100, doorDayBrightness)), forKey: "HUD.Ambient.v90_3.doorDayBrightness") }
    }
    var doorNightBrightness: Int {
        didSet { UserDefaults.standard.set(max(0, min(100, doorNightBrightness)), forKey: "HUD.Ambient.v90_3.doorNightBrightness") }
    }

    var shutdownFadeSeconds: Double {
        didSet { UserDefaults.standard.set(max(0.4, min(10.0, shutdownFadeSeconds)), forKey: "HUD.Ambient.v90.shutdownFade") }
    }
    var engineOffConfirmationSeconds: Double {
        didSet { UserDefaults.standard.set(max(0.5, min(8.0, engineOffConfirmationSeconds)), forKey: "HUD.Ambient.v90.engineOffConfirmation") }
    }

    private(set) var vehicleAutomationStatus = "Idle — waiting for engine-switched HUD power"
    private(set) var enginePowerPresent = false
    private(set) var enginePowerStatus = "Engine power unknown — waiting for HUD / OBD"
    private(set) var vehicleSessionActive = false
    private(set) var vehicleHeadlightsActive = false
    private(set) var vehicleShutdownLatched = false

    private var startupClassificationTask: Task<Void, Never>?
    private var headlightJoinTask: Task<Void, Never>?
    private var vehicleAnimationTask: Task<Void, Never>?
    private var doorBrightnessTask: Task<Void, Never>?
    private var vehicleStartupCompleted = false
    private var vehicleJoinedHeadlightIDs: Set<UUID> = []
    private var allPowerAbsentSince: Date?
    private var previousHeadlightPowerPresent = false
    private var hudEnginePowerSignalPresent = false
    private var obdEnginePowerSignalPresent = false
    private var engineOffConfirmationTask: Task<Void, Never>?
    private var hudOutageBeganAt: Date?
    /// v90.4: engine-start timestamp anchors the courtesy-headlight settling
    /// window. Headlight advertisements from before this instant are explicitly
    /// ignored when classifying the startup as day or night.
    private var enginePowerBecamePresentAt: Date?
    private var directOBDLastSeen = Date.distantPast
    private var directOBDPeripheralID: UUID?
    private var directOBDWitnessProven: Bool
    private let directOBDRecentSeconds: TimeInterval = 3.0
    private let directOBDAcquireWindowSeconds: TimeInterval = 3.0
    private(set) var independentOBDWitnessStatus = "Independent OBD witness not calibrated"

    // MARK: - v90 controller state

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

    /// v90.5 diagnostics for the still-undecoded BLEDIM2 application protocol.
    /// The controller exposes FFF0/FFF1, but the command payload is intentionally
    /// not guessed after physical testing disproved the old FFE0/FFE1-family frames.
    private(set) var bledimDeviceInfoByID: [UUID: [String: String]] = [:]
    private(set) var bledimAdvertisementSummaryByID: [UUID: String] = [:]
    private var bledimLastAdvertisementSignatureByID: [UUID: String] = [:]

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
        self.vehicleAutomationEnabled = d.object(forKey: "HUD.Ambient.v90.vehicleAutomation") == nil
            ? false : d.bool(forKey: "HUD.Ambient.v90.vehicleAutomation")
        self.vehicleStartupCycles = d.object(forKey: "HUD.Ambient.v90.startupCycles") == nil
            ? 1 : max(1, min(2, d.integer(forKey: "HUD.Ambient.v90.startupCycles")))
        self.vehicleStartupPulseDurationSeconds = d.object(forKey: "HUD.Ambient.v90.startupDuration") == nil
            ? 1.5 : max(0.4, min(6.0, d.double(forKey: "HUD.Ambient.v90.startupDuration")))
        self.startupClassificationSeconds = d.object(forKey: "HUD.Ambient.v90.classification") == nil
            ? 4.0 : max(1.0, min(8.0, d.double(forKey: "HUD.Ambient.v90.classification")))
        self.headlightJoinFadeSeconds = d.object(forKey: "HUD.Ambient.v90.headlightFade") == nil
            ? 1.5 : max(0.4, min(6.0, d.double(forKey: "HUD.Ambient.v90.headlightFade")))
        self.doorDayBrightness = d.object(forKey: "HUD.Ambient.v90_3.doorDayBrightness") == nil
            ? 100 : max(0, min(100, d.integer(forKey: "HUD.Ambient.v90_3.doorDayBrightness")))
        self.doorNightBrightness = d.object(forKey: "HUD.Ambient.v90_3.doorNightBrightness") == nil
            ? 45 : max(0, min(100, d.integer(forKey: "HUD.Ambient.v90_3.doorNightBrightness")))
        self.shutdownFadeSeconds = d.object(forKey: "HUD.Ambient.v90.shutdownFade") == nil
            ? 2.0 : max(0.4, min(10.0, d.double(forKey: "HUD.Ambient.v90.shutdownFade")))
        self.engineOffConfirmationSeconds = d.object(forKey: "HUD.Ambient.v90.engineOffConfirmation") == nil
            ? 2.0 : max(0.5, min(8.0, d.double(forKey: "HUD.Ambient.v90.engineOffConfirmation")))
        self.directOBDWitnessProven = d.bool(forKey: "HUD.Ambient.v90_2.directOBDWitnessProven")
        if let raw = d.string(forKey: "HUD.Ambient.v90_2.directOBDPeripheralUUID") {
            self.directOBDPeripheralID = UUID(uuidString: raw)
        } else {
            self.directOBDPeripheralID = nil
        }
        self.pairedDevices = Self.decode([AmbientLightDevice].self, key: "HUD.Ambient.v89.pairedDevices") ?? []
        self.groups = Self.decode([AmbientLightGroup].self, key: "HUD.Ambient.v89.groups") ?? []

        super.init()

        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "HUDAmbientCentral.v45"]
        )

        migrateLegacyBLEDOMPairingIfNeeded()
        migrateKnownVehicleRoles()
        independentOBDWitnessStatus = directOBDWitnessProven
            ? "Independent OBD BLE witness calibrated"
            : "Not calibrated — switch only the HUD off once while the engine stays on"
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

    private static func knownVehicleRole(for id: UUID) -> AmbientLightRole? {
        let upper = id.uuidString.uppercased()
        if upper.hasPrefix("FBD8C9A0-") { return .door }
        if upper.hasPrefix("7A3B5F81-") { return .dashboard }
        if upper.hasPrefix("51FA23D6-") { return .centerConsole }
        return nil
    }

    /// v90 knows the three controllers from the supplied physical test. This is
    /// only a migration convenience; the role remains editable in the UI.
    private func migrateKnownVehicleRoles() {
        var changed = false
        for index in pairedDevices.indices where pairedDevices[index].role == nil {
            if let role = Self.knownVehicleRole(for: pairedDevices[index].id) {
                pairedDevices[index].role = role
                changed = true
                logger.log("AMBIENT ROLE", "Auto-assigned \(pairedDevices[index].displayName) → \(role.displayName)")
            }
        }
        if changed { persistPairedDevices() }
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
        startupClassificationTask?.cancel()
        startupClassificationTask = nil
        headlightJoinTask?.cancel()
        headlightJoinTask = nil
        vehicleAnimationTask?.cancel()
        vehicleAnimationTask = nil
        doorBrightnessTask?.cancel()
        doorBrightnessTask = nil
        engineOffConfirmationTask?.cancel()
        engineOffConfirmationTask = nil

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
                protocolKind: kind,
                role: Self.knownVehicleRole(for: discovered.id)
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

    func setRole(_ id: UUID, to role: AmbientLightRole?) {
        updateDevice(id) { $0.role = role }
        logger.log("AMBIENT ROLE", "\(pairedDevice(id)?.displayName ?? id.uuidString) → \(role?.displayName ?? "Unassigned")")
        evaluateVehicleLightingAutomation()
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
        guard let device = pairedDevice(id) else { return false }
        // v90.5: FFF1 transport is proven for BLEDIM2, but the command payload is
        // not. Treat it as diagnostic-only until an official traffic capture is
        // replayed successfully; vehicle automation must never send guessed bytes.
        if device.protocolKind == .bledim2 { return false }
        if device.protocolKind == .lotusLantern && isEncryptedLotusName(device.advertisedName) { return false }
        return isConnected(id) && writeCharacteristicsByID[id] != nil
    }

    func isBLEDIMRawTransportReady(_ id: UUID) -> Bool {
        guard let device = pairedDevice(id), device.protocolKind == .bledim2 else { return false }
        return isConnected(id) && writeCharacteristicsByID[id] != nil
    }

    func isLogicallyPowered(_ id: UUID) -> Bool {
        guard pairedDevice(id) != nil else { return false }
        let recentlyAdvertised = lastSeenByID[id].map { Date().timeIntervalSince($0) <= 8 } ?? false
        let connected = peripheralsByID[id]?.state == .connected
        return recentlyAdvertised || connected
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

        if state == "Connected" && writeCharacteristicsByID[id] != nil {
            return device.protocolKind == .bledim2
                ? "Connected • FFF1 transport ready • commands not decoded"
                : "Connected • control ready"
        }
        if state == "Connected" && writeCharacteristicsByID[id] == nil {
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

    func bledimDeviceInfoSummary(_ id: UUID) -> String {
        guard let values = bledimDeviceInfoByID[id], !values.isEmpty else {
            return "Waiting for readable Device Information values…"
        }
        return values.keys.sorted().map { "\($0): \(values[$0] ?? "")" }.joined(separator: "\n")
    }

    func bledimAdvertisementSummary(_ id: UUID) -> String {
        bledimAdvertisementSummaryByID[id] ?? "Waiting for advertisement metadata…"
    }

    func refreshBLEDIMDiagnostics(_ id: UUID) {
        guard let device = pairedDevice(id), device.protocolKind == .bledim2,
              let peripheral = peripheralsByID[id], peripheral.state == .connected else {
            controllerStatus = "Connect the BLEDIM device before refreshing diagnostics"
            return
        }
        logger.log("AMBIENT INFO", "Refreshing BLEDIM GATT + Device Information diagnostics for \(device.displayName)")
        peripheral.discoverServices(nil)
    }

    /// v90.5 protocol-lab escape hatch. This writes ONLY to the already-verified
    /// FFF1 application characteristic. It never touches the TI F000FFC0 OAD
    /// firmware-update service. The user can paste bytes recovered from an Android
    /// Bluetooth HCI snoop capture and test them without rebuilding the iOS app.
    @discardableResult
    func sendRawBLEDIMHex(_ id: UUID, hex: String) -> String {
        guard let device = pairedDevice(id), device.protocolKind == .bledim2 else {
            return "This device is not configured as BLEDIM2 / FFF1"
        }
        guard isBLEDIMRawTransportReady(id),
              let peripheral = peripheralsByID[id],
              let characteristic = writeCharacteristicsByID[id] else {
            return "FFF1 transport is not ready"
        }

        var compact = hex
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
        for separator in [" ", "\n", "\t", ",", ":", "-"] {
            compact = compact.replacingOccurrences(of: separator, with: "")
        }
        guard !compact.isEmpty, compact.count % 2 == 0, compact.count <= 128,
              compact.allSatisfy({ $0.isHexDigit }) else {
            return "Enter 1–64 bytes of hexadecimal data (for example: AA 01 02 55)"
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(compact.count / 2)
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            guard let value = UInt8(compact[index..<next], radix: 16) else {
                return "Invalid hexadecimal packet"
            }
            bytes.append(value)
            index = next
        }
        let data = Data(bytes)
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
        logger.log("AMBIENT RAW", "BLEDIM FFF1 replay \(device.displayName) bytes=\(bytes.count): \(Self.hex(data))")
        return "Sent \(bytes.count) byte\(bytes.count == 1 ? "" : "s") to FFF1"
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
        updateDevice(id) {
            $0.brightness = clamped
            $0.lastAppliedBrightness = clamped
        }
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

    func setVehicleStartupCycles(_ cycles: Int) { vehicleStartupCycles = max(1, min(2, cycles)) }
    func setVehicleStartupPulseDuration(_ seconds: Double) { vehicleStartupPulseDurationSeconds = max(0.4, min(6.0, seconds)) }
    func setStartupClassificationDuration(_ seconds: Double) { startupClassificationSeconds = max(1.0, min(8.0, seconds)) }
    func setHeadlightJoinFadeDuration(_ seconds: Double) { headlightJoinFadeSeconds = max(0.4, min(6.0, seconds)) }

    func setDoorDayBrightness(_ percent: Int) {
        doorDayBrightness = max(0, min(100, percent))
        applyDoorTargetAfterSettingChange(changedNightTarget: false)
    }

    func setDoorNightBrightness(_ percent: Int) {
        doorNightBrightness = max(0, min(100, percent))
        applyDoorTargetAfterSettingChange(changedNightTarget: true)
    }

    func setShutdownFadeDuration(_ seconds: Double) { shutdownFadeSeconds = max(0.4, min(10.0, seconds)) }
    func setEngineOffConfirmationDuration(_ seconds: Double) { engineOffConfirmationSeconds = max(0.5, min(8.0, seconds)) }

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
        guard device.protocolKind == .lotusLantern else {
            logger.log("AMBIENT CTRL", "BLEDIM write blocked until FFF1 payload is captured: power \(on ? "ON" : "OFF") \(reason) for \(device.displayName)")
            return
        }
        writeAmbient(LotusLanternProtocol.power(on), to: id, label: "power \(on ? "ON" : "OFF") \(reason)")
    }

    private func sendColor(_ id: UUID, color: AmbientRGB, reason: String) {
        guard let device = pairedDevice(id) else { return }
        guard device.protocolKind == .lotusLantern else {
            logger.log("AMBIENT CTRL", "BLEDIM write blocked until FFF1 payload is captured: RGB \(color.red),\(color.green),\(color.blue) \(reason) for \(device.displayName)")
            return
        }
        writeAmbient(
            LotusLanternProtocol.color(color),
            to: id,
            label: "RGB \(color.red),\(color.green),\(color.blue) \(reason)"
        )
    }

    private func sendBrightness(_ id: UUID, percent: Int, reason: String) {
        guard let device = pairedDevice(id) else { return }
        let clamped = max(0, min(100, percent))
        guard device.protocolKind == .lotusLantern else {
            logger.log("AMBIENT CTRL", "BLEDIM write blocked until FFF1 payload is captured: brightness \(clamped)% \(reason) for \(device.displayName)")
            return
        }
        writeAmbient(
            LotusLanternProtocol.brightness(clamped),
            to: id,
            label: "brightness \(clamped)% \(reason)"
        )
    }

    /// Sends runtime brightness without changing the user's preferred steady-state
    /// brightness. This is the key invariant for vehicle shutdown: physical/last
    /// applied state may end at zero while the next startup still knows its target.
    private func applyRuntimeBrightness(_ id: UUID, percent: Int, reason: String, persist: Bool = false) {
        let clamped = max(0, min(100, percent))
        if let index = pairedDevices.firstIndex(where: { $0.id == id }) {
            // Fade loops can emit dozens of frames in a couple of seconds. Keep the
            // observable runtime state current, but avoid serializing the entire
            // paired-device array to UserDefaults on every animation step.
            pairedDevices[index].lastAppliedBrightness = clamped
            if persist { persistPairedDevices() }
        }
        sendBrightness(id, percent: clamped, reason: reason)
    }

    private func writeAmbient(_ data: Data, to id: UUID, label: String) {
        guard let device = pairedDevice(id) else { return }
        if device.protocolKind == .lotusLantern && isEncryptedLotusName(device.advertisedName) {
            logger.log("AMBIENT CTRL", "Blocked encrypted ELK-* write for \(device.displayName); encrypted dialect is not enabled")
            return
        }
        guard let peripheral = peripheralsByID[id], peripheral.state == .connected,
              let characteristic = writeCharacteristicsByID[id] else {
            logger.log("AMBIENT CTRL", "Cannot send \(label) to \(device.displayName): control characteristic unavailable")
            return
        }

        let writeType: CBCharacteristicWriteType
        if characteristic.properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else if characteristic.properties.contains(.write) {
            writeType = .withResponse
        } else {
            logger.log("AMBIENT CTRL", "Control characteristic is not writable for \(device.displayName)")
            return
        }

        peripheral.writeValue(data, for: characteristic, type: writeType)
        logger.log("AMBIENT TX", "\(device.displayName) \(label): \(Self.hex(data))")
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
        guard let device = pairedDevice(id), isControllable(id) else { return }
        sendColor(id, color: device.color, reason: "restore")
        let runtimeTarget = vehicleAutomationEnabled ? device.runtimeBrightness : device.brightness
        applyRuntimeBrightness(id, percent: runtimeTarget, reason: "restore")
        sendPower(id, on: device.powerOn, reason: "restore")
    }

    private func runStartupAnimationIfNeeded(_ id: UUID, force: Bool = false) {
        guard let device = pairedDevice(id),
              isControllable(id) else { return }

        // Vehicle-aware mode owns synchronization across all three lights. Never
        // let a single-device reconnect independently replay the old pulse.
        guard !vehicleAutomationEnabled else {
            vehicleControlBecameReady(id)
            return
        }

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
            self.applyRuntimeBrightness(id, percent: 0, reason: "startup")

            @MainActor
            func fade(from: Int, to: Int) async -> Bool {
                for step in 1...steps {
                    guard !Task.isCancelled else { return false }
                    let fraction = Double(step) / Double(steps)
                    let value = Int((Double(from) + (Double(to - from) * fraction)).rounded())
                    self.applyRuntimeBrightness(id, percent: value, reason: "startup fade")
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
            self.applyRuntimeBrightness(id, percent: target, reason: "startup final", persist: true)
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

    // MARK: - Vehicle-aware choreography

    private func deviceID(for role: AmbientLightRole) -> UUID? {
        pairedDevices.first(where: { $0.role == role })?.id
    }

    private func roleIDs(_ roles: Set<AmbientLightRole>) -> [UUID] {
        pairedDevices.compactMap { device in
            guard let role = device.role, roles.contains(role) else { return nil }
            return device.id
        }
    }

    private func headlightPowerPresent() -> Bool {
        // Steady-state driving detector. Either headlight-fed controller is
        // sufficient, and the normal 8-second logical-presence hysteresis keeps
        // brief BLE dropouts from changing the door brightness.
        roleIDs([.dashboard, .centerConsole]).contains(where: { isLogicallyPowered($0) })
    }

    /// Startup classification intentionally does NOT use the normal 8-second
    /// logical-presence hysteresis. On this vehicle, entering the car powers the
    /// Dashboard and Center Console lights before the engine starts regardless of
    /// daylight. A daylight engine start then removes that headlight power.
    ///
    /// Therefore, a startup counts as night only when at least one headlight-fed
    /// controller is still actively connected after engine power appears, or it
    /// produced a fresh advertisement AFTER engine power appeared. Pre-engine
    /// courtesy-light advertisements cannot make a daylight start look like night.
    private func startupHeadlightPowerPresent(now: Date = Date()) -> Bool {
        let engineOnAt = enginePowerBecamePresentAt ?? now
        return roleIDs([.dashboard, .centerConsole]).contains { id in
            if peripheralsByID[id]?.state == .connected {
                return true
            }
            guard let seen = lastSeenByID[id], seen >= engineOnAt else { return false }
            return now.timeIntervalSince(seen) <= 2.0
        }
    }

    private func doorTargetBrightness(night: Bool) -> Int {
        max(0, min(100, night ? doorNightBrightness : doorDayBrightness))
    }

    var doorBrightnessModeStatus: String {
        if !vehicleAutomationEnabled {
            return "Door day/night automation off • day \(doorDayBrightness)% • night \(doorNightBrightness)%"
        }
        guard enginePowerPresent else {
            return "Engine off • pre-engine courtesy headlights are ignored for day/night classification"
        }
        let night = vehicleStartupCompleted ? vehicleHeadlightsActive : startupHeadlightPowerPresent()
        let target = doorTargetBrightness(night: night)
        return "\(night ? "Night" : "Day") door target \(target)% • after startup, night = Dashboard OR Center Console present"
    }

    private func vehicleTargetBrightness(for device: AmbientLightDevice, night: Bool) -> Int {
        if device.role == .door {
            return doorTargetBrightness(night: night)
        }
        return max(0, min(100, device.brightness))
    }

    private func allRolePowerAbsent() -> Bool {
        let ids = pairedDevices.compactMap { $0.role == nil ? nil : $0.id }
        guard !ids.isEmpty else { return true }
        return ids.allSatisfy { !isLogicallyPowered($0) }
    }

    private func applyDoorTargetAfterSettingChange(changedNightTarget: Bool) {
        guard vehicleAutomationEnabled,
              enabled,
              enginePowerPresent,
              vehicleSessionActive,
              vehicleStartupCompleted,
              !vehicleShutdownLatched else { return }

        let night = headlightPowerPresent()
        guard night == changedNightTarget else { return }
        transitionDoorBrightness(
            to: doorTargetBrightness(night: night),
            over: headlightJoinFadeSeconds,
            reason: night ? "night target changed" : "day target changed"
        )
    }

    private func resetVehicleAutomationRuntime(reason: String) {
        startupClassificationTask?.cancel()
        startupClassificationTask = nil
        headlightJoinTask?.cancel()
        headlightJoinTask = nil
        vehicleAnimationTask?.cancel()
        vehicleAnimationTask = nil
        engineOffConfirmationTask?.cancel()
        engineOffConfirmationTask = nil
        hudOutageBeganAt = nil
        if !enginePowerPresent { enginePowerBecamePresentAt = nil }
        vehicleSessionActive = false
        vehicleStartupCompleted = false
        vehicleHeadlightsActive = false
        previousHeadlightPowerPresent = false
        vehicleShutdownLatched = false
        vehicleJoinedHeadlightIDs.removeAll()
        allPowerAbsentSince = nil
        vehicleAutomationStatus = vehicleAutomationEnabled
            ? (enginePowerPresent ? "Engine power ON — waiting for door-light power" : "Idle — waiting for engine-switched HUD power")
            : "Vehicle automation disabled"
        logger.log("AMBIENT AUTO", "Vehicle automation runtime reset: \(reason)")
    }

    /// The HUD and OBD2 adapter share the engine-switched power domain, but the
    /// HUD can thermally reboot while the engine remains on. A HUD disconnect by
    /// itself therefore NEVER means engine OFF. While the HUD is absent, the app
    /// looks for the OBD2 adapter directly in the ambient CoreBluetooth scan.
    /// Once that independent witness has been observed/calibrated, its continued
    /// BLE presence vetoes shutdown during HUD-only outages. If the witness has
    /// never been calibrated, automatic shutdown is inhibited rather than risking
    /// a false fade while driving.
    func hudTransportPowerSignal(_ present: Bool) {
        hudEnginePowerSignalPresent = present
        if present {
            hudOutageBeganAt = nil
            confirmEnginePowerOn(source: "HUD transport")
        } else {
            hudOutageBeganAt = Date()
            engineOffConfirmationTask?.cancel()
            engineOffConfirmationTask = nil
            if isDirectOBDRecentlyPresent() {
                confirmEnginePowerOn(source: "independent OBD BLE witness")
            } else if directOBDWitnessProven {
                enginePowerStatus = "HUD unavailable • waiting for independent OBD witness"
                logger.log("AMBIENT ENGINE", "HUD transport lost; waiting for calibrated independent OBD witness before considering engine OFF")
            } else {
                enginePowerStatus = "HUD unavailable • OBD witness not calibrated • auto-shutdown inhibited"
                logger.log("AMBIENT ENGINE", "HUD transport lost, but independent OBD witness is not calibrated; refusing automatic engine-OFF decision")
            }
        }
    }

    func obdPowerSignal(_ present: Bool) {
        obdEnginePowerSignalPresent = present
        if present {
            confirmEnginePowerOn(source: "OBD2 connected through HUD")
        } else if hudEnginePowerSignalPresent {
            // The HUD itself still proves that the engine-switched power domain is ON.
            confirmEnginePowerOn(source: "HUD transport")
        } else {
            evaluateIndependentOBDWitnessForEngineState()
        }
    }

    private func currentOBDTargetName() -> String {
        let stored = UserDefaults.standard.string(forKey: "HUD.OBD.deviceName") ?? "OBDII"
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "OBDII" : trimmed
    }

    private func matchesIndependentOBDWitness(id: UUID, name: String) -> Bool {
        if let known = directOBDPeripheralID, known == id { return true }
        let target = currentOBDTargetName()
        guard !name.isEmpty, !target.isEmpty else { return false }
        return name.localizedCaseInsensitiveContains(target)
    }

    private func recordIndependentOBDWitness(id: UUID, name: String, rssi: Int) {
        directOBDLastSeen = Date()
        directOBDPeripheralID = id
        if !directOBDWitnessProven {
            directOBDWitnessProven = true
            UserDefaults.standard.set(true, forKey: "HUD.Ambient.v90_2.directOBDWitnessProven")
            UserDefaults.standard.set(id.uuidString, forKey: "HUD.Ambient.v90_2.directOBDPeripheralUUID")
            logger.log("AMBIENT ENGINE", "Calibrated independent OBD BLE witness name=\(name.isEmpty ? currentOBDTargetName() : name) id=\(id)")
        }
        independentOBDWitnessStatus = "OBD witness present • \(name.isEmpty ? currentOBDTargetName() : name) • \(rssi) dBm"
        if !hudEnginePowerSignalPresent {
            confirmEnginePowerOn(source: "independent OBD BLE witness")
        }
    }

    private func isDirectOBDRecentlyPresent(now: Date = Date()) -> Bool {
        directOBDWitnessProven && now.timeIntervalSince(directOBDLastSeen) <= directOBDRecentSeconds
    }

    private func evaluateIndependentOBDWitnessForEngineState(now: Date = Date()) {
        if hudEnginePowerSignalPresent || obdEnginePowerSignalPresent {
            confirmEnginePowerOn(source: hudEnginePowerSignalPresent ? "HUD transport" : "OBD2 connected through HUD")
            return
        }

        if isDirectOBDRecentlyPresent(now: now) {
            engineOffConfirmationTask?.cancel()
            engineOffConfirmationTask = nil
            confirmEnginePowerOn(source: "independent OBD BLE witness")
            return
        }

        guard directOBDWitnessProven else {
            engineOffConfirmationTask?.cancel()
            engineOffConfirmationTask = nil
            enginePowerStatus = "HUD unavailable • OBD witness not calibrated • auto-shutdown inhibited"
            return
        }

        // Give a powered OBD adapter a few seconds to resume advertising after
        // its HUD-side Bluetooth link disappears. This is the discriminator
        // between a HUD-only reboot and the whole engine-switched domain losing power.
        if let began = hudOutageBeganAt, now.timeIntervalSince(began) < directOBDAcquireWindowSeconds {
            enginePowerStatus = "HUD unavailable • checking OBD power witness…"
            return
        }

        scheduleEnginePowerOffConfirmation(source: "HUD absent and calibrated OBD witness absent")
    }

    private func confirmEnginePowerOn(source: String) {
        engineOffConfirmationTask?.cancel()
        engineOffConfirmationTask = nil
        let wasOff = !enginePowerPresent
        enginePowerPresent = true
        enginePowerStatus = "Engine power ON • \(source)"

        if wasOff {
            enginePowerBecamePresentAt = Date()
            startupClassificationTask?.cancel()
            startupClassificationTask = nil
            headlightJoinTask?.cancel()
            headlightJoinTask = nil
            vehicleAnimationTask?.cancel()
            vehicleAnimationTask = nil
            vehicleSessionActive = false
            vehicleStartupCompleted = false
            vehicleHeadlightsActive = false
            previousHeadlightPowerPresent = false
            vehicleShutdownLatched = false
            vehicleJoinedHeadlightIDs.removeAll()
            allPowerAbsentSince = nil
            vehicleAutomationStatus = "Engine power ON • waiting for door + courtesy-headlight settle"
            logger.log("AMBIENT ENGINE", "Engine-switched power ON via \(source); courtesy-headlight state before engine will be ignored for startup classification")
        }

        evaluateVehicleLightingAutomation()
    }

    private func scheduleEnginePowerOffConfirmation(source: String) {
        guard enginePowerPresent else {
            enginePowerStatus = "Engine power OFF / unavailable"
            return
        }
        guard !hudEnginePowerSignalPresent, !obdEnginePowerSignalPresent else {
            enginePowerStatus = hudEnginePowerSignalPresent
                ? "Engine power ON • HUD transport"
                : "Engine power ON • OBD2 connected through HUD"
            return
        }
        guard directOBDWitnessProven else {
            enginePowerStatus = "HUD unavailable • OBD witness not calibrated • auto-shutdown inhibited"
            return
        }
        guard !isDirectOBDRecentlyPresent() else {
            confirmEnginePowerOn(source: "independent OBD BLE witness")
            return
        }
        guard engineOffConfirmationTask == nil else { return }

        let delay = max(0.5, engineOffConfirmationSeconds)
        enginePowerStatus = "Engine power OFF candidate • OBD witness absent • confirming \(String(format: "%.1f", delay))s"
        logger.log("AMBIENT ENGINE", "\(source); calibrated OBD witness absent; confirming engine OFF for \(String(format: "%.1f", delay))s")
        engineOffConfirmationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled,
                  !self.hudEnginePowerSignalPresent,
                  !self.obdEnginePowerSignalPresent,
                  !self.isDirectOBDRecentlyPresent() else { return }
            self.engineOffConfirmationTask = nil
            self.confirmEnginePowerOff()
        }
    }

    private func confirmEnginePowerOff() {
        guard enginePowerPresent else { return }
        enginePowerPresent = false
        enginePowerStatus = "Engine power OFF • HUD + calibrated OBD witness absent"
        independentOBDWitnessStatus = directOBDWitnessProven
            ? "Calibrated OBD witness absent"
            : "Independent OBD witness not calibrated"
        logger.log("AMBIENT ENGINE", "Engine-switched power OFF confirmed only after HUD loss + calibrated independent OBD witness absence")

        if vehicleAutomationEnabled, !vehicleShutdownLatched {
            // Arm the shutdown latch even if no light was controllable at this exact
            // instant. In daylight the Dashboard/Console may power up only after the
            // driver exits/locks the car; they must still be suppressed when they
            // appear  later during the courtesy-headlight interval.
            performVehicleShutdownFade(trigger: "engine power OFF")
        } else if vehicleAutomationEnabled {
            vehicleAutomationStatus = "Engine power OFF • courtesy-light suppression armed"
        }
    }

    /// Called by the watchdog and after role/presence changes. Ambient-light BLE
    /// presence still drives day/night/headlight state, while engine ON/OFF comes
    /// from the separately powered HUD/OBD signals above.
    private func evaluateVehicleLightingAutomation() {
        guard vehicleAutomationEnabled, enabled else { return }

        guard enginePowerPresent else {
            vehicleAutomationStatus = vehicleShutdownLatched
                ? "Engine power OFF • headlight courtesy suppression armed"
                : "Waiting for engine-switched HUD / OBD power"
            return
        }

        if allRolePowerAbsent() {
            if allPowerAbsentSince == nil { allPowerAbsentSince = Date() }
            if let since = allPowerAbsentSince, Date().timeIntervalSince(since) >= 15,
               vehicleSessionActive || vehicleShutdownLatched {
                resetVehicleAutomationRuntime(reason: "all three light power sources absent for 15s")
            }
        } else {
            allPowerAbsentSince = nil
        }

        guard !vehicleShutdownLatched else {
            vehicleAutomationStatus = "Shutdown latch active — suppressing headlight-fed courtesy lights until next engine ON"
            return
        }

        let doorPresent = deviceID(for: .door).map { isLogicallyPowered($0) } ?? false
        let headlightsPresent = headlightPowerPresent()

        if !vehicleSessionActive && doorPresent && startupClassificationTask == nil {
            beginVehicleStartupClassification()
            return
        }

        if vehicleSessionActive && vehicleStartupCompleted {
            if !previousHeadlightPowerPresent && headlightsPresent {
                scheduleHeadlightJoinFade()
            } else if previousHeadlightPowerPresent && !headlightsPresent {
                vehicleJoinedHeadlightIDs.subtract(roleIDs([.dashboard, .centerConsole]))
                vehicleHeadlightsActive = false
                transitionDoorBrightness(
                    to: doorTargetBrightness(night: false),
                    over: headlightJoinFadeSeconds,
                    reason: "headlights off → daytime door brightness"
                )
                vehicleAutomationStatus = "Driving • headlights off • door returning to daytime brightness"
                logger.log("AMBIENT AUTO", "Headlight-fed lights lost physical power; door fading to daytime target \(doorDayBrightness)%. No fade-out command is possible for the now-unpowered headlight lights.")
            }
        }
        previousHeadlightPowerPresent = headlightsPresent
    }

    private func beginVehicleStartupClassification() {
        vehicleSessionActive = true
        vehicleStartupCompleted = false
        vehicleShutdownLatched = false

        // The Dashboard/Console may have been powered before the engine because
        // the vehicle turns its courtesy headlights on when the driver enters.
        // Do not treat that pre-engine condition as night. The classification
        // deadline is anchored to the engine-power transition, not to whenever
        // the Door BLE connection happens to finish.
        let now = Date()
        let engineOnAt = enginePowerBecamePresentAt ?? now
        let elapsedSinceEngineOn = max(0, now.timeIntervalSince(engineOnAt))
        let remainingSettle = max(0.5, startupClassificationSeconds - elapsedSinceEngineOn)

        previousHeadlightPowerPresent = false
        vehicleAutomationStatus = "Engine ON • settling courtesy headlights for day/night classification…"
        logger.log(
            "AMBIENT AUTO",
            "Post-engine startup settle begin; configured=\(String(format: "%.1f", startupClassificationSeconds))s elapsed=\(String(format: "%.1f", elapsedSinceEngineOn))s remaining=\(String(format: "%.1f", remainingSettle))s. Pre-engine Dashboard/Console presence is ignored."
        )

        // Once the engine session begins, move any currently controllable role
        // light to zero. At night they remain electrically powered and will take
        // part in the synchronized pulse. In daylight the headlight-fed pair will
        // lose physical power during the settling window, leaving Door only.
        for id in pairedDevices.compactMap({ $0.role == nil ? nil : $0.id }) where isControllable(id) {
            prepareForVehicleStartup(id)
        }

        startupClassificationTask?.cancel()
        startupClassificationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(remainingSettle))
            guard !Task.isCancelled, self.vehicleAutomationEnabled, !self.vehicleShutdownLatched else { return }
            self.startupClassificationTask = nil
            self.finishVehicleStartupClassification()
        }
    }

    private func finishVehicleStartupClassification() {
        let nightStart = startupHeadlightPowerPresent()
        let roleSet: Set<AmbientLightRole> = nightStart
            ? [.door, .dashboard, .centerConsole]
            : [.door]
        let ids = roleIDs(roleSet).filter { isLogicallyPowered($0) && isControllable($0) }

        vehicleHeadlightsActive = nightStart
        previousHeadlightPowerPresent = nightStart
        vehicleStartupCompleted = true
        if nightStart {
            // Only mark controllers that actually reached a writable state in
            // this synchronized startup. A physically powered controller whose
            // GATT setup finishes later must still be eligible for the normal
            // headlight-join fade rather than being silently considered joined.
            vehicleJoinedHeadlightIDs.formUnion(ids.filter {
                pairedDevice($0)?.role?.isHeadlightFed == true
            })
            vehicleAutomationStatus = "Night startup • headlight-fed lights remained powered after engine start"
            logger.log("AMBIENT AUTO", "Night startup classified after post-engine settle; at least one headlight-fed controller remained powered, pulsing available role lights together")
        } else {
            vehicleAutomationStatus = "Day startup • courtesy headlights turned off after engine start"
            logger.log("AMBIENT AUTO", "Day startup classified after post-engine settle; headlight-fed controllers lost power, pulsing Door only")
        }
        runVehicleStartupPulse(ids: ids, label: nightStart ? "night startup" : "day startup")
    }

    private func prepareForVehicleStartup(_ id: UUID) {
        guard let device = pairedDevice(id), isControllable(id) else { return }
        sendPower(id, on: true, reason: "vehicle startup prepare")
        sendColor(id, color: device.color, reason: "vehicle startup prepare")
        applyRuntimeBrightness(id, percent: 0, reason: "vehicle startup prepare")
    }

    private func runVehicleStartupPulse(ids: [UUID], label: String) {
        let ids = ids.filter { isControllable($0) }
        guard !ids.isEmpty else {
            vehicleAutomationStatus += " • waiting for BLE control readiness"
            return
        }

        vehicleAnimationTask?.cancel()
        let cycles = max(1, min(2, vehicleStartupCycles))
        let duration = max(0.4, vehicleStartupPulseDurationSeconds)
        vehicleAnimationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for id in ids {
                guard let device = self.pairedDevice(id) else { continue }
                self.sendPower(id, on: true, reason: label)
                self.sendColor(id, color: device.color, reason: label)
                self.applyRuntimeBrightness(id, percent: 0, reason: "\(label) start")
            }

            let steps = 12
            let halfFade = max(0.2, duration / 2.0)
            let stepDelay = halfFade / Double(steps)

            let nightTarget = self.vehicleHeadlightsActive
            let targets = Dictionary(uniqueKeysWithValues: ids.compactMap { id -> (UUID, Int)? in
                guard let device = self.pairedDevice(id) else { return nil }
                return (id, self.vehicleTargetBrightness(for: device, night: nightTarget))
            })

            @MainActor
            func fade(fractionFrom start: Double, to end: Double) async -> Bool {
                for step in 1...steps {
                    guard !Task.isCancelled else { return false }
                    let t = Double(step) / Double(steps)
                    let fraction = start + ((end - start) * t)
                    for id in ids {
                        let target = targets[id] ?? 0
                        let value = Int((Double(target) * fraction).rounded())
                        self.applyRuntimeBrightness(id, percent: value, reason: "\(label) synchronized fade")
                    }
                    try? await Task.sleep(for: .seconds(stepDelay))
                }
                return true
            }

            for _ in 0..<cycles {
                guard await fade(fractionFrom: 0, to: 1) else { return }
                guard await fade(fractionFrom: 1, to: 0) else { return }
            }
            guard await fade(fractionFrom: 0, to: 1) else { return }
            for id in ids {
                let target = targets[id] ?? 0
                self.applyRuntimeBrightness(id, percent: target, reason: "\(label) final vehicle target", persist: true)
            }
            self.vehicleAnimationTask = nil
            self.vehicleAutomationStatus = self.vehicleHeadlightsActive
                ? "Driving • headlights on • door at night target \(self.doorNightBrightness)%"
                : "Driving • daylight • door at day target \(self.doorDayBrightness)%"
            self.logger.log("AMBIENT AUTO", "Vehicle startup pulse complete: \(label)")
        }
    }

    private func scheduleHeadlightJoinFade() {
        guard headlightJoinTask == nil else { return }
        vehicleHeadlightsActive = true
        vehicleAutomationStatus = "Headlights detected • preparing dashboard + console fade-in"
        headlightJoinTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Coalesce the two headlight-fed BLE controllers, which may become
            // ready a fraction of a second apart even though power arrived together.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, self.vehicleAutomationEnabled, !self.vehicleShutdownLatched else { return }
            self.headlightJoinTask = nil
            self.fadeInNewHeadlightDevices()
        }
    }

    private func fadeInNewHeadlightDevices() {
        // Night is true when EITHER headlight-fed controller is present. Dim the
        // always-powered door light independently of whether both headlight GATT
        // paths are writable yet.
        transitionDoorBrightness(
            to: doorTargetBrightness(night: true),
            over: headlightJoinFadeSeconds,
            reason: "headlights on → nighttime door brightness"
        )

        let candidates = roleIDs([.dashboard, .centerConsole]).filter {
            isLogicallyPowered($0) && isControllable($0) && !vehicleJoinedHeadlightIDs.contains($0)
        }
        vehicleHeadlightsActive = true

        guard !candidates.isEmpty else {
            vehicleAutomationStatus = "Driving • headlights on • door dimming to night target; waiting for headlight-light control"
            logger.log("AMBIENT AUTO", "Headlight OFF→ON; door target=\(doorNightBrightness)% while headlight-fed controllers wait for control readiness")
            return
        }

        vehicleJoinedHeadlightIDs.formUnion(candidates)
        fade(ids: candidates, toPreferredOver: headlightJoinFadeSeconds, reason: "headlight join")
        vehicleAutomationStatus = "Driving • headlights on • dashboard + console joining; door → \(doorNightBrightness)%"
        logger.log("AMBIENT AUTO", "Headlight OFF→ON; fading in \(candidates.count) headlight-fed light(s) and dimming door to \(doorNightBrightness)%")
    }

    private func transitionDoorBrightness(to targetPercent: Int, over seconds: Double, reason: String) {
        guard !vehicleShutdownLatched,
              let doorID = deviceID(for: .door),
              isLogicallyPowered(doorID),
              isControllable(doorID),
              let door = pairedDevice(doorID) else { return }

        let target = max(0, min(100, targetPercent))
        let start = door.runtimeBrightness

        doorBrightnessTask?.cancel()
        if start == target {
            applyRuntimeBrightness(doorID, percent: target, reason: "\(reason) already at target", persist: true)
            return
        }

        sendPower(doorID, on: true, reason: reason)
        sendColor(doorID, color: door.color, reason: reason)
        logger.log("AMBIENT AUTO", "Door brightness transition \(start)% → \(target)% reason=\(reason)")

        doorBrightnessTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let steps = 16
            let delay = max(0.4, seconds) / Double(steps)
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let t = Double(step) / Double(steps)
                let value = Int((Double(start) + (Double(target - start) * t)).rounded())
                self.applyRuntimeBrightness(doorID, percent: value, reason: reason)
                try? await Task.sleep(for: .seconds(delay))
            }
            self.applyRuntimeBrightness(doorID, percent: target, reason: "\(reason) final", persist: true)
            self.doorBrightnessTask = nil
            self.logger.log("AMBIENT AUTO", "Door brightness transition complete at \(target)% reason=\(reason)")
        }
    }

    private func fade(ids: [UUID], toPreferredOver seconds: Double, reason: String) {
        let ids = ids.filter { isControllable($0) }
        guard !ids.isEmpty else { return }
        vehicleAnimationTask?.cancel()
        vehicleAnimationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for id in ids {
                guard let device = self.pairedDevice(id) else { continue }
                self.sendPower(id, on: true, reason: reason)
                self.sendColor(id, color: device.color, reason: reason)
                self.applyRuntimeBrightness(id, percent: 0, reason: "\(reason) start")
            }
            let steps = 16
            let delay = max(0.4, seconds) / Double(steps)
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let fraction = Double(step) / Double(steps)
                for id in ids {
                    guard let device = self.pairedDevice(id) else { continue }
                    let value = Int((Double(device.brightness) * fraction).rounded())
                    self.applyRuntimeBrightness(id, percent: value, reason: reason)
                }
                try? await Task.sleep(for: .seconds(delay))
            }
            for id in ids {
                guard let device = self.pairedDevice(id) else { continue }
                self.applyRuntimeBrightness(id, percent: device.brightness, reason: "\(reason) final preferred", persist: true)
            }
            self.vehicleAnimationTask = nil
        }
    }

    /// Manual test entry point; automatic engine-power shutdown uses the same
    /// implementation so there is only one fade-to-zero path to validate.
    func fadeOutForVehicleShutdown() {
        guard vehicleAutomationEnabled else {
            vehicleAutomationStatus = "Enable vehicle automation first"
            return
        }
        performVehicleShutdownFade(trigger: "manual Fade Out Now")
    }

    private func performVehicleShutdownFade(trigger: String) {
        guard vehicleAutomationEnabled else { return }
        startupClassificationTask?.cancel()
        startupClassificationTask = nil
        headlightJoinTask?.cancel()
        headlightJoinTask = nil
        vehicleAnimationTask?.cancel()
        doorBrightnessTask?.cancel()
        doorBrightnessTask = nil

        // Corrected physical shutdown sequence (v90.5): the Door controller is on
        // the engine-switched circuit and loses electrical power immediately when
        // the engine turns off. There is no opportunity to transmit a fade to it.
        // Record runtime zero locally without overwriting its Day/Night targets.
        if let doorID = deviceID(for: .door),
           let index = pairedDevices.firstIndex(where: { $0.id == doorID }) {
            pairedDevices[index].lastAppliedBrightness = 0
            persistPairedDevices()
            logger.log("AMBIENT AUTO", "Engine OFF: Door power is expected to disappear immediately; runtime recorded as 0 without sending a fade")
        }

        // Only the headlight-fed pair can still be electrically alive after engine
        // OFF. At night they remain on; after a daylight lock they can turn on again
        // for the courtesy-headlight interval. Verified protocols are faded now; any
        // later verified reconnect is held at zero by vehicleControlBecameReady().
        let poweredHeadlightDevices = pairedDevices.filter { device in
            guard let role = device.role, role.isHeadlightFed else { return false }
            return isLogicallyPowered(device.id)
        }
        let ids = poweredHeadlightDevices.filter { isControllable($0.id) }.map(\.id)
        let undecodedPowered = poweredHeadlightDevices.filter { $0.protocolKind == .bledim2 && !isControllable($0.id) }
        vehicleShutdownLatched = true
        vehicleAutomationStatus = "\(trigger) • suppressing headlight-fed courtesy lights"
        logger.log(
            "AMBIENT AUTO",
            "Shutdown trigger=\(trigger); Door expected power-off immediately; fading \(ids.count) powered controllable headlight-fed light(s) to 0; \(undecodedPowered.count) powered BLEDIM headlight-fed light(s) cannot yet be commanded. Shutdown latch remains until next engine ON so later courtesy lights can be held at zero once their protocol is decoded."
        )
        for device in undecodedPowered {
            logger.log("AMBIENT AUTO", "Courtesy suppression unavailable for \(device.displayName): BLEDIM FFF1 command payload not decoded")
        }

        guard !ids.isEmpty else {
            if !undecodedPowered.isEmpty {
                vehicleAutomationStatus = enginePowerPresent
                    ? "Manual shutdown preview • BLEDIM headlight control not decoded"
                    : "Engine power OFF • suppression armed, but BLEDIM headlight control is not decoded"
            } else {
                vehicleAutomationStatus = enginePowerPresent
                    ? "Manual shutdown preview • no controllable headlight-fed lights currently powered"
                    : "Engine power OFF • courtesy-light suppression armed"
            }
            return
        }

        vehicleAnimationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let starts = Dictionary(uniqueKeysWithValues: ids.compactMap { id in
                self.pairedDevice(id).map { (id, $0.runtimeBrightness) }
            })
            let steps = 20
            let delay = max(0.4, self.shutdownFadeSeconds) / Double(steps)
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let remaining = 1.0 - (Double(step) / Double(steps))
                for id in ids {
                    let start = starts[id] ?? 0
                    self.applyRuntimeBrightness(
                        id,
                        percent: Int((Double(start) * remaining).rounded()),
                        reason: "vehicle shutdown headlight fade"
                    )
                }
                try? await Task.sleep(for: .seconds(delay))
            }
            for id in ids {
                self.applyRuntimeBrightness(id, percent: 0, reason: "vehicle shutdown headlight final", persist: true)
            }
            self.vehicleAnimationTask = nil
            self.vehicleAutomationStatus = self.enginePowerPresent
                ? "Manual shutdown preview complete • Door unchanged physically"
                : "Engine power OFF • headlight-fed courtesy lights held at 0%"
            self.logger.log("AMBIENT AUTO", "Headlight-fed shutdown fade complete trigger=\(trigger); preferred targets unchanged; shutdown latch remains armed")
        }
    }

    /// Convenient stationary test without power-cycling the car. It reclassifies
    /// the currently powered set as day/night and runs the configured startup pulse.
    func previewVehicleStartupNow() {
        guard vehicleAutomationEnabled else { return }
        vehicleShutdownLatched = false
        vehicleSessionActive = true
        vehicleStartupCompleted = true
        finishVehicleStartupClassification()
    }

    func restorePreferredBrightnessNow() {
        vehicleShutdownLatched = false
        let nonDoorIDs = pairedDevices.compactMap { device -> UUID? in
            guard device.role != nil,
                  device.role != .door,
                  isLogicallyPowered(device.id),
                  isControllable(device.id) else { return nil }
            return device.id
        }
        fade(ids: nonDoorIDs, toPreferredOver: headlightJoinFadeSeconds, reason: "restore preferred")
        transitionDoorBrightness(
            to: doorTargetBrightness(night: headlightPowerPresent()),
            over: headlightJoinFadeSeconds,
            reason: "restore current door day/night target"
        )
        vehicleAutomationStatus = "Restoring current brightness targets"
    }

    private func vehicleControlBecameReady(_ id: UUID) {
        guard vehicleAutomationEnabled, let device = pairedDevice(id), device.role != nil else {
            restoreDeviceState(id)
            return
        }
        if vehicleShutdownLatched {
            if device.role == .door {
                if let index = pairedDevices.firstIndex(where: { $0.id == id }) {
                    pairedDevices[index].lastAppliedBrightness = 0
                    persistPairedDevices()
                }
                logger.log("AMBIENT AUTO", "Door control appeared while shutdown latched; no command sent because Door should be engine-power OFF")
                return
            }
            if let role = device.role, role.isHeadlightFed {
                sendColor(id, color: device.color, reason: "post-lock courtesy suppression")
                sendPower(id, on: true, reason: "post-lock courtesy suppression")
                applyRuntimeBrightness(id, percent: 0, reason: "post-lock courtesy keep zero", persist: true)
                logger.log("AMBIENT AUTO", "Headlight-fed light appeared while engine OFF; held at 0% for courtesy/headlight delay")
            }
            return
        }
        if startupClassificationTask != nil && !vehicleStartupCompleted {
            prepareForVehicleStartup(id)
            return
        }
        if vehicleSessionActive && vehicleStartupCompleted,
           device.role == .door {
            transitionDoorBrightness(
                to: doorTargetBrightness(night: headlightPowerPresent()),
                over: headlightJoinFadeSeconds,
                reason: "door control ready"
            )
            return
        }
        if vehicleSessionActive && vehicleStartupCompleted,
           let role = device.role, role.isHeadlightFed, headlightPowerPresent(),
           !vehicleJoinedHeadlightIDs.contains(id) {
            fadeInNewHeadlightDevices()
            return
        }
        restoreDeviceState(id)
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
            self.captureBLEDIMAdvertisement(
                id: id,
                name: name,
                rssi: RSSI.intValue,
                serviceUUIDs: advertisedServices,
                advertisementData: advertisementData
            )

            if self.matchesIndependentOBDWitness(id: id, name: name) {
                self.recordIndependentOBDWitness(id: id, name: name, rssi: RSSI.intValue)
            }

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
            self.evaluateVehicleLightingAutomation()
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
            self.lastSeenByID[id] = Date()
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
            self.evaluateVehicleLightingAutomation()
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
            self.evaluateVehicleLightingAutomation()
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

                if let device = self.pairedDevice(id), device.protocolKind == .bledim2,
                   characteristic.properties.contains(.read) {
                    let serviceValue = service.uuid.uuidString.uppercased()
                    // Read standard Device Information + Battery values. These are
                    // diagnostics only; never read/write the TI OAD firmware service.
                    if serviceValue == "180A" || serviceValue == "180F" {
                        peripheral.readValue(for: characteristic)
                    }
                }

                if let device = self.pairedDevice(id) {
                    let writable = characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)
                    let matchesControl: Bool
                    switch device.protocolKind {
                    case .lotusLantern:
                        matchesControl = self.isLotusService(service.uuid) && self.isLotusWriteCharacteristic(characteristic.uuid)
                    case .bledim2:
                        matchesControl = self.isBLEDIMService(service.uuid) && self.isBLEDIMWriteCharacteristic(characteristic.uuid)
                    }
                    if matchesControl && writable {
                        if self.writeCharacteristicsByID[id] == nil { newlyReady = true }
                        self.writeCharacteristicsByID[id] = characteristic
                        if characteristic.properties.contains(.notify) {
                            peripheral.setNotifyValue(true, for: characteristic)
                        }
                    }
                }
            }
            self.characteristicUUIDsByID[id] = set

            if newlyReady, let device = self.pairedDevice(id) {
                if device.protocolKind == .bledim2 {
                    self.controllerStatus = "\(device.displayName) FFF1 transport ready • payload capture required"
                    self.logger.log(
                        "AMBIENT CTRL",
                        "BLEDIM2 FFF0/FFF1 raw transport ready for \(device.displayName); automatic writes disabled after v90 packet-family mismatch"
                    )
                } else {
                    self.controllerStatus = "\(device.displayName) control ready"
                    self.logger.log("AMBIENT CTRL", "Lotus Lantern FFF0/FFF3 verified control ready for \(device.displayName)")
                    self.runStartupAnimationIfNeeded(id)
                }
                self.evaluateVehicleLightingAutomation()
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.logger.log("AMBIENT RX", "Notify/read failed \(peripheral.identifier) char=\(characteristic.uuid.uuidString): \(error.localizedDescription)")
                return
            }
            guard let value = characteristic.value else { return }
            if self.pairedDevice(peripheral.identifier)?.protocolKind == .bledim2 {
                self.recordBLEDIMDiagnosticValue(
                    peripheralID: peripheral.identifier,
                    characteristic: characteristic,
                    value: value
                )
            }
            self.logger.log("AMBIENT RX", "\(peripheral.identifier) char=\(characteristic.uuid.uuidString): \(Self.hex(value))")
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

    private func recordBLEDIMDiagnosticValue(
        peripheralID: UUID,
        characteristic: CBCharacteristic,
        value: Data
    ) {
        let uuid = characteristic.uuid.uuidString.uppercased()
        let labels: [String: String] = [
            "2A29": "Manufacturer",
            "2A24": "Model",
            "2A25": "Serial",
            "2A27": "Hardware revision",
            "2A26": "Firmware revision",
            "2A28": "Software revision",
            "2A23": "System ID",
            "2A2A": "IEEE data",
            "2A50": "PnP ID",
            "2A19": "Battery"
        ]
        guard let label = labels[uuid] else { return }

        let rendered: String
        if uuid == "2A19", let first = value.first {
            rendered = "\(first)% (hex \(Self.hex(value)))"
        } else if ["2A29", "2A24", "2A25", "2A27", "2A26", "2A28"].contains(uuid),
                  let text = String(data: value, encoding: .utf8)?
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.controlCharacters)),
                  !text.isEmpty {
            rendered = "\(text) (hex \(Self.hex(value)))"
        } else {
            rendered = Self.hex(value)
        }

        var values = bledimDeviceInfoByID[peripheralID] ?? [:]
        guard values[label] != rendered else { return }
        values[label] = rendered
        bledimDeviceInfoByID[peripheralID] = values
        logger.log("AMBIENT INFO", "BLEDIM \(peripheralID) \(label)=\(rendered)")
    }

    private func captureBLEDIMAdvertisement(
        id: UUID,
        name: String,
        rssi: Int,
        serviceUUIDs: [String],
        advertisementData: [String: Any]
    ) {
        guard pairedDevice(id)?.protocolKind == .bledim2 else { return }

        let manufacturer = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)
            .map(Self.hex) ?? "—"
        let serviceData = (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:])
            .map { "\($0.key.uuidString.uppercased())=\(Self.hex($0.value))" }
            .sorted()
            .joined(separator: ",")
        let txPower = (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)
            .map { String($0.intValue) } ?? "—"
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)
            .map { $0.boolValue ? "true" : "false" } ?? "—"
        let services = serviceUUIDs.sorted().joined(separator: ",")
        let metadataSignature = "name=\(name)|services=\(services)|mfg=\(manufacturer)|serviceData=\(serviceData)|tx=\(txPower)|connectable=\(connectable)"
        let summary = "name=\(name.isEmpty ? "(unnamed)" : name)\nRSSI=\(rssi) dBm\nservices=\(services.isEmpty ? "—" : services)\nmanufacturer=\(manufacturer)\nserviceData=\(serviceData.isEmpty ? "—" : serviceData)\ntxPower=\(txPower)\nconnectable=\(connectable)"
        bledimAdvertisementSummaryByID[id] = summary

        if bledimLastAdvertisementSignatureByID[id] != metadataSignature {
            bledimLastAdvertisementSignatureByID[id] = metadataSignature
            logger.log(
                "AMBIENT ADV",
                "BLEDIM \(id) metadata name=\(name.isEmpty ? "(unnamed)" : name) services=\(services.isEmpty ? "—" : services) manufacturer=\(manufacturer) serviceData=\(serviceData.isEmpty ? "—" : serviceData) txPower=\(txPower) connectable=\(connectable)"
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

    private func isBLEDIMService(_ uuid: CBUUID) -> Bool {
        let value = uuid.uuidString.uppercased()
        return value == "FFF0" || value == BLEDIM2Protocol.serviceUUID.uppercased()
    }

    private func isBLEDIMWriteCharacteristic(_ uuid: CBUUID) -> Bool {
        let value = uuid.uuidString.uppercased()
        return value == "FFF1" || value == BLEDIM2Protocol.writeCharacteristicUUID.uppercased()
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

                self.evaluateIndependentOBDWitnessForEngineState()
                self.evaluateVehicleLightingAutomation()
            }
        }
    }
}

import Foundation
import CoreBluetooth
import Observation

/// v90.8 keeps the verified Lotus + BLEDIM2 control path while simplifying vehicle
/// behavior around three concepts: smooth brightness transitions, one synchronized
/// power-up breath animation, and Door day/night brightness while the engine session
/// is active. Bluetooth discovery remains active in the background even though the
/// nearby-device list is hidden from the normal UI.
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

    var startupClassificationSeconds: Double {
        didSet { UserDefaults.standard.set(max(1.0, min(8.0, startupClassificationSeconds)), forKey: "HUD.Ambient.v90.classification") }
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

    var engineOffConfirmationSeconds: Double {
        didSet { UserDefaults.standard.set(max(0.5, min(8.0, engineOffConfirmationSeconds)), forKey: "HUD.Ambient.v90.engineOffConfirmation") }
    }

    /// v90.8 shared transition profile. Every manual brightness change and every
    /// automatic Door day/night change uses this same smooth interpolation duration.
    var brightnessTransitionSeconds: Double {
        didSet { UserDefaults.standard.set(max(1.0, min(15.0, brightnessTransitionSeconds)), forKey: "HUD.Ambient.v90_8.transitionDuration") }
    }

    /// One global power-up animation profile keeps multiple lights on a common timebase.
    var breathCycles: Int {
        didSet { UserDefaults.standard.set(max(2, min(5, breathCycles)), forKey: "HUD.Ambient.v90_8.breathCycles") }
    }
    var breathDurationSeconds: Double {
        didSet { UserDefaults.standard.set(max(1.0, min(15.0, breathDurationSeconds)), forKey: "HUD.Ambient.v90_8.breathDuration") }
    }

    // MARK: - Finite ambient overspeed warning

    var overspeedWarningEnabled: Bool {
        didSet {
            UserDefaults.standard.set(overspeedWarningEnabled, forKey: "HUD.Ambient.v90_12.overspeed.enabled")
            if !overspeedWarningEnabled {
                cancelOverspeedWarning(restoreIfPossible: true, reason: "warning disabled")
                overspeedCrossingBaselineValid = false
                overspeedLastWarningTriggeredAt = nil
            }
        }
    }

    var overspeedWarningLight: AmbientOverspeedWarningLight {
        didSet {
            UserDefaults.standard.set(overspeedWarningLight.rawValue, forKey: "HUD.Ambient.v90_12.overspeed.light")
            cancelOverspeedWarning(restoreIfPossible: true, reason: "warning light changed")
            overspeedCrossingBaselineValid = false
        }
    }

    var overspeedWarningOffsetMph: Int {
        didSet {
            UserDefaults.standard.set(max(0, min(20, overspeedWarningOffsetMph)), forKey: "HUD.Ambient.v90_12.overspeed.offsetMph")
            overspeedCrossingBaselineValid = false
        }
    }

    var overspeedWarningBrightness: Int {
        didSet {
            UserDefaults.standard.set(max(10, min(100, overspeedWarningBrightness)), forKey: "HUD.Ambient.v90_12.overspeed.brightness")
        }
    }

    var overspeedWarningColor: AmbientRGB {
        didSet {
            if let data = try? JSONEncoder().encode(overspeedWarningColor) {
                UserDefaults.standard.set(data, forKey: "HUD.Ambient.v90_13.overspeed.color")
            }
        }
    }

    var overspeedWarningPulseCount: Int {
        didSet {
            UserDefaults.standard.set(max(2, min(3, overspeedWarningPulseCount)), forKey: "HUD.Ambient.v90_12.overspeed.pulses")
        }
    }

    var overspeedWarningPulseDurationSeconds: Double {
        didSet {
            UserDefaults.standard.set(max(0.0, min(5.0, overspeedWarningPulseDurationSeconds)), forKey: "HUD.Ambient.v90_12.overspeed.pulseDuration")
        }
    }

    private(set) var overspeedWarningStatus = "Armed — waiting for a valid speed limit"

    private(set) var vehicleAutomationStatus = "Idle — waiting for engine-switched HUD power"
    private(set) var enginePowerPresent = false
    private(set) var enginePowerStatus = "Engine power unknown — waiting for HUD / OBD"
    private(set) var vehicleSessionActive = false
    private(set) var vehicleHeadlightsActive = false

    private var startupClassificationTask: Task<Void, Never>?
    private var vehicleStartupCompleted = false
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

    /// BLEDIM2 diagnostics remain available even though v90.7 has recovered the
    /// application command protocol. They are useful for confirming firmware/GATT
    /// consistency across the Door and Dashboard controllers.
    private(set) var bledimDeviceInfoByID: [UUID: [String: String]] = [:]
    private(set) var bledimAdvertisementSummaryByID: [UUID: String] = [:]
    private var bledimLastAdvertisementSignatureByID: [UUID: String] = [:]

    /// Official BLEDIM2 uses a monotonically increasing one-byte sequence field.
    /// The packet capture only proved the counter for one peripheral, so v90.9
    /// keeps a separate counter per BLEDIM connection. This avoids interleaving
    /// Dashboard and Door into +2 sequence jumps during synchronized animation.
    private var bledimSequenceByID: [UUID: UInt8] = [:]

    /// Repeated service discovery was previously being triggered by the 2-second
    /// connection watchdog even after a controller was fully ready. During a fade
    /// that meant Device Information reads and characteristic callbacks competing
    /// with animation writes on the main actor. Discovery is now only repeated when
    /// the control characteristic is missing, with a short retry cooldown.
    private var lastServiceDiscoveryRequestByID: [UUID: Date] = [:]
    private let serviceDiscoveryRetrySeconds: TimeInterval = 5.0

    /// BLEDIM2 FFF1 sends an all-FF notification for many control writes. Logging
    /// every one synchronously to disk can itself make a 10-Hz animation stutter.
    /// Keep the latest diagnostic value but rate-limit repetitive file logging.
    private var lastBLEDIMNotifyLogAtByID: [UUID: Date] = [:]

    private var animationTasks: [UUID: Task<Void, Never>] = [:]
    private var brightnessTransitionTasks: [UUID: Task<Void, Never>] = [:]
    private var animatedConnectionSession: Set<UUID> = []
    private var sessionResetTasks: [UUID: Task<Void, Never>] = [:]

    /// All enabled lights that power up close together share one breath timeline.
    /// A late GATT-ready device can join the active timeline instead of starting an
    /// independent animation several seconds out of phase.
    private var synchronizedBreathTask: Task<Void, Never>?
    private var pendingBreathStartTask: Task<Void, Never>?
    private var activeBreathIDs: Set<UUID> = []
    private var activeBreathStartBrightness: [UUID: Int] = [:]
    /// Final steady-state target for the last leg of the breath. Normally this is
    /// the brightness at animation start. If the user/vehicle changes the target
    /// while the breath is running, only the final leg of the last repetition
    /// returns to that new target so the animation stays smooth.
    private var activeBreathReturnBrightness: [UUID: Int] = [:]
    private var activeBreathStartedAt: Date?

    /// v90.10 transport reliability. Power/color/final-brightness writes are
    /// semantically important and must never be dropped merely because a
    /// write-without-response controller temporarily applies backpressure.
    private var restoreTasks: [UUID: Task<Void, Never>] = [:]
    private var breathPrepareTasks: [UUID: Task<Void, Never>] = [:]

    /// Dashboard + Center Console share the physical headlight circuit. Treat a
    /// new physical ON epoch as the animation trigger, rather than a 15-second BLE
    /// reconnect heuristic. This also lets a quick OFF -> ON start a fresh breath.
    private var headlightPowerSessionActive = false
    private var headlightPowerEpoch = 0
    private var headlightStateGeneration = 0
    private var headlightAnimatedEpochByID: [UUID: Int] = [:]

    /// v90.14: Center + Dashboard are a two-sensor physical-power consensus.
    /// Mixed evidence is intentionally "unknown" and never flips the confirmed
    /// vehicle headlight state. Both ON or both OFF must remain stable before
    /// committing an edge.
    private var headlightConsensusTask: Task<Void, Never>?
    private let headlightConsensusStabilitySeconds: TimeInterval = 0.75
    private let headlightRecentEvidenceSeconds: TimeInterval = 0.50

    /// Finite overspeed overlay. It never sends a Power OFF command.
    private var overspeedWarningTask: Task<Void, Never>?
    private var overspeedRestoreTask: Task<Void, Never>?
    private var overspeedWarningGeneration = 0
    private var overspeedWarningActiveID: UUID?
    private var overspeedAboveThreshold = false
    private var overspeedCrossingBaselineValid = false
    private var overspeedLastLimitAvailable = false
    private var overspeedLastWarningTriggeredAt: Date?
    private let overspeedWarningCooldownSeconds: TimeInterval = 60.0

    /// UI deep-link token used by the persistent Ambient shortcut.
    private(set) var pairedLightsFocusRequest = 0

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
        self.startupClassificationSeconds = d.object(forKey: "HUD.Ambient.v90.classification") == nil
            ? 4.0 : max(1.0, min(8.0, d.double(forKey: "HUD.Ambient.v90.classification")))
        self.doorDayBrightness = d.object(forKey: "HUD.Ambient.v90_3.doorDayBrightness") == nil
            ? 100 : max(0, min(100, d.integer(forKey: "HUD.Ambient.v90_3.doorDayBrightness")))
        self.doorNightBrightness = d.object(forKey: "HUD.Ambient.v90_3.doorNightBrightness") == nil
            ? 45 : max(0, min(100, d.integer(forKey: "HUD.Ambient.v90_3.doorNightBrightness")))
        self.engineOffConfirmationSeconds = d.object(forKey: "HUD.Ambient.v90.engineOffConfirmation") == nil
            ? 2.0 : max(0.5, min(8.0, d.double(forKey: "HUD.Ambient.v90.engineOffConfirmation")))
        self.brightnessTransitionSeconds = d.object(forKey: "HUD.Ambient.v90_8.transitionDuration") == nil
            ? 3.0 : max(1.0, min(15.0, d.double(forKey: "HUD.Ambient.v90_8.transitionDuration")))
        self.breathCycles = d.object(forKey: "HUD.Ambient.v90_8.breathCycles") == nil
            ? 2 : max(2, min(5, d.integer(forKey: "HUD.Ambient.v90_8.breathCycles")))
        self.breathDurationSeconds = d.object(forKey: "HUD.Ambient.v90_8.breathDuration") == nil
            ? 6.0 : max(1.0, min(15.0, d.double(forKey: "HUD.Ambient.v90_8.breathDuration")))
        self.overspeedWarningEnabled = d.object(forKey: "HUD.Ambient.v90_12.overspeed.enabled") == nil
            ? false : d.bool(forKey: "HUD.Ambient.v90_12.overspeed.enabled")
        self.overspeedWarningLight = AmbientOverspeedWarningLight(
            rawValue: d.string(forKey: "HUD.Ambient.v90_12.overspeed.light") ?? ""
        ) ?? .door
        self.overspeedWarningOffsetMph = d.object(forKey: "HUD.Ambient.v90_12.overspeed.offsetMph") == nil
            ? 5 : max(0, min(20, d.integer(forKey: "HUD.Ambient.v90_12.overspeed.offsetMph")))
        self.overspeedWarningBrightness = d.object(forKey: "HUD.Ambient.v90_12.overspeed.brightness") == nil
            ? 100 : max(10, min(100, d.integer(forKey: "HUD.Ambient.v90_12.overspeed.brightness")))
        self.overspeedWarningColor = Self.decode(AmbientRGB.self, key: "HUD.Ambient.v90_13.overspeed.color")
            ?? AmbientRGB(red: 255, green: 0, blue: 0)
        self.overspeedWarningPulseCount = d.object(forKey: "HUD.Ambient.v90_12.overspeed.pulses") == nil
            ? 3 : max(2, min(3, d.integer(forKey: "HUD.Ambient.v90_12.overspeed.pulses")))
        self.overspeedWarningPulseDurationSeconds = d.object(forKey: "HUD.Ambient.v90_12.overspeed.pulseDuration") == nil
            ? 0.9 : max(0.0, min(5.0, d.double(forKey: "HUD.Ambient.v90_12.overspeed.pulseDuration")))
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
        brightnessTransitionTasks.values.forEach { $0.cancel() }
        brightnessTransitionTasks.removeAll()
        synchronizedBreathTask?.cancel()
        synchronizedBreathTask = nil
        pendingBreathStartTask?.cancel()
        pendingBreathStartTask = nil
        activeBreathIDs.removeAll()
        activeBreathStartBrightness.removeAll()
        activeBreathReturnBrightness.removeAll()
        activeBreathStartedAt = nil
        sessionResetTasks.values.forEach { $0.cancel() }
        sessionResetTasks.removeAll()
        restoreTasks.values.forEach { $0.cancel() }
        restoreTasks.removeAll()
        breathPrepareTasks.values.forEach { $0.cancel() }
        breathPrepareTasks.removeAll()
        headlightConsensusTask?.cancel()
        headlightConsensusTask = nil
        overspeedWarningTask?.cancel()
        overspeedWarningTask = nil
        overspeedRestoreTask?.cancel()
        overspeedRestoreTask = nil
        startupClassificationTask?.cancel()
        startupClassificationTask = nil
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
            lastServiceDiscoveryRequestByID[id] = nil
            discoverServicesIfNeeded(peripheral, force: true, reason: "protocol changed")
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
                ? "Connected • BLEDIM2 FFF1 control ready"
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
        discoverServicesIfNeeded(peripheral, force: true, reason: "manual diagnostics refresh")
    }

    /// Advanced protocol-lab escape hatch. This writes ONLY to the verified FFF1
    /// application characteristic and never touches the TI F000FFC0 OAD service.
    /// Normal operation uses BLEDIM2Protocol; raw replay is retained for diagnostics.
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

    func requestPairedLightsFocus() {
        pairedLightsFocusRequest &+= 1
    }

    func setPower(_ id: UUID, on: Bool) {
        cancelBrightnessTransition(for: id)
        breathPrepareTasks[id]?.cancel()
        breathPrepareTasks[id] = nil
        restoreTasks[id]?.cancel()
        restoreTasks[id] = nil
        removeFromActiveBreath(id)
        updateDevice(id) { $0.powerOn = on }

        // A user-requested OFF -> ON is also a real light power-up event. If this
        // light has Animation enabled, the Breath preparation owns the reliable
        // Power ON write. Otherwise send the power command with backpressure retry.
        if on, pairedDevice(id)?.startupAnimationEnabled == true, isControllable(id) {
            animatedConnectionSession.remove(id)
            queuePowerUpBreath(id, force: true)
        } else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await self.sendPowerWhenReady(id, on: on, reason: "manual")
            }
        }
    }

    func setColor(_ id: UUID, color: AmbientRGB) {
        updateDevice(id) { $0.color = color }
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.sendColorWhenReady(id, color: color, reason: "manual")
        }
    }

    /// Manual brightness changes always interpolate from the last applied runtime
    /// value to the new preferred target. The target is persisted immediately; the
    /// runtime value is persisted only when the transition reaches its final frame.
    func setBrightness(_ id: UUID, percent: Int) {
        let clamped = max(0, min(100, percent))
        updateDevice(id) { $0.brightness = clamped }

        // If a power-up breath is already in progress, do not cancel it or jump
        // brightness. Preserve the requested breath path and make the final leg of
        // the LAST repetition land smoothly on the newly selected target.
        if activeBreathIDs.contains(id) {
            activeBreathReturnBrightness[id] = clamped
            logger.log("AMBIENT ANIM", "Breath final target updated to \(clamped)% by manual brightness")
            return
        }

        transitionBrightness(
            ids: [id],
            targets: [id: clamped],
            over: brightnessTransitionSeconds,
            reason: "manual brightness"
        )
    }

    func setStartupAnimationEnabled(_ id: UUID, enabled: Bool) {
        updateDevice(id) { $0.startupAnimationEnabled = enabled }
    }

    // Retained for persisted/source compatibility with pre-v90.8 builds. The new UI
    // uses one global breath profile so enabled lights can share a common timeline.
    func setStartupCycles(_ id: UUID, cycles: Int) {
        updateDevice(id) { $0.startupCycles = max(2, min(5, cycles)) }
    }

    func setStartupDuration(_ id: UUID, seconds: Double) {
        updateDevice(id) { $0.startupDurationSeconds = max(1.0, min(15.0, seconds)) }
    }

    func setStartupClassificationDuration(_ seconds: Double) { startupClassificationSeconds = max(1.0, min(8.0, seconds)) }
    func setBrightnessTransitionDuration(_ seconds: Double) { brightnessTransitionSeconds = max(1.0, min(15.0, seconds)) }
    func setBreathCycles(_ cycles: Int) { breathCycles = max(2, min(5, cycles)) }
    func setBreathDuration(_ seconds: Double) { breathDurationSeconds = max(1.0, min(15.0, seconds)) }

    func setOverspeedWarningOffset(_ mph: Int) {
        overspeedWarningOffsetMph = max(0, min(20, mph))
    }

    func setOverspeedWarningBrightness(_ percent: Int) {
        overspeedWarningBrightness = max(10, min(100, percent))
    }

    func setOverspeedWarningColor(_ color: AmbientRGB) {
        overspeedWarningColor = color
    }

    func setOverspeedWarningPulseCount(_ count: Int) {
        overspeedWarningPulseCount = max(2, min(3, count))
    }

    func setOverspeedWarningPulseDuration(_ seconds: Double) {
        overspeedWarningPulseDurationSeconds = max(0.0, min(5.0, seconds))
    }

    func setDoorDayBrightness(_ percent: Int) {
        doorDayBrightness = max(0, min(100, percent))
        applyDoorTargetAfterSettingChange(changedNightTarget: false)
    }

    func setDoorNightBrightness(_ percent: Int) {
        doorNightBrightness = max(0, min(100, percent))
        applyDoorTargetAfterSettingChange(changedNightTarget: true)
    }

    func setEngineOffConfirmationDuration(_ seconds: Double) { engineOffConfirmationSeconds = max(0.5, min(8.0, seconds)) }

    func previewStartupAnimation(_ id: UUID) {
        animatedConnectionSession.remove(id)
        queuePowerUpBreath(id, force: true)
    }

    func setDevicePresetColor(_ id: UUID, slot: Int, color: AmbientRGB) {
        guard (0..<5).contains(slot) else { return }
        updateDevice(id) { device in
            var presets = device.resolvedPresetColors
            presets[slot] = color
            device.presetColors = presets
        }
        logger.log("AMBIENT PRESET", "Saved device preset \(slot + 1) for \(pairedDevice(id)?.displayName ?? id.uuidString) = \(color.red),\(color.green),\(color.blue)")
    }

    func setGroupPresetColor(_ groupID: UUID, slot: Int, color: AmbientRGB) {
        guard (0..<5).contains(slot), let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        var presets = groups[index].resolvedPresetColors
        presets[slot] = color
        groups[index].presetColors = presets
        persistGroups()
        logger.log("AMBIENT PRESET", "Saved group preset \(slot + 1) for \(groups[index].name) = \(color.red),\(color.green),\(color.blue)")
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
        let clamped = max(0, min(100, percent))
        let ids = group.memberIDs.filter { pairedDevice($0) != nil }
        guard !ids.isEmpty else { return }
        for id in ids {
            if let index = pairedDevices.firstIndex(where: { $0.id == id }) {
                pairedDevices[index].brightness = clamped
            }
        }
        persistPairedDevices()

        let breathing = ids.filter { activeBreathIDs.contains($0) }
        for id in breathing { activeBreathReturnBrightness[id] = clamped }
        if !breathing.isEmpty {
            logger.log("AMBIENT ANIM", "Breath final target updated to \(clamped)% for \(breathing.count) group member(s)")
        }

        let steady = ids.filter { !activeBreathIDs.contains($0) }
        if !steady.isEmpty {
            transitionBrightness(
                ids: steady,
                targets: Dictionary(uniqueKeysWithValues: steady.map { ($0, clamped) }),
                over: brightnessTransitionSeconds,
                reason: "group manual brightness"
            )
        }
    }

    private func updateDevice(_ id: UUID, mutation: (inout AmbientLightDevice) -> Void) {
        guard let index = pairedDevices.firstIndex(where: { $0.id == id }) else { return }
        mutation(&pairedDevices[index])
        persistPairedDevices()
    }

    private func cancelBrightnessTransition(for id: UUID) {
        brightnessTransitionTasks[id]?.cancel()
        brightnessTransitionTasks[id] = nil
    }

    private func animationWriteInterval(for id: UUID) -> TimeInterval {
        // v90.10 uses the same 20-Hz visual clock for both protocols. BLEDIM2 has a
        // 0...255 brightness channel, so retaining the full clock plus raw-byte
        // interpolation is noticeably smoother near minimum brightness. CoreBluetooth
        // backpressure still gates every actual write; stale animation frames are
        // skipped instead of queued.
        0.05
    }

    private func animationLevelSignature(for id: UUID, normalized: Double) -> Int {
        let level = max(0.0, min(1.0, normalized))
        if pairedDevice(id)?.protocolKind == .bledim2 {
            return Int((level * 255.0).rounded())
        }
        return Int((level * 100.0).rounded())
    }

    private func transitionBrightness(
        ids requestedIDs: [UUID],
        targets: [UUID: Int],
        over seconds: Double,
        reason: String
    ) {
        let ids = requestedIDs.filter { isControllable($0) && targets[$0] != nil }
        guard !ids.isEmpty else {
            logger.log("AMBIENT FADE", "Transition queued/saved but no requested light is currently controllable: \(reason)")
            return
        }

        for id in ids {
            cancelBrightnessTransition(for: id)
            removeFromActiveBreath(id)
        }

        let starts = Dictionary(uniqueKeysWithValues: ids.compactMap { id in
            pairedDevice(id).map { (id, $0.runtimeBrightness) }
        })
        let duration = max(1.0, min(15.0, seconds))
        let timelineTick = 0.05

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastSentLevel: [UUID: Int] = [:]
            var lastWriteAt: [UUID: Date] = [:]
            let startedAt = Date()
            self.logger.log(
                "AMBIENT FADE",
                "Smooth brightness transition begin ids=\(ids.count) duration=\(String(format: "%.1f", duration))s reason=\(reason) protocolPacing=20Hz/rawBLEDIM"
            )

            while true {
                guard !Task.isCancelled else { return }
                let now = Date()
                let elapsed = now.timeIntervalSince(startedAt)
                let t = min(1.0, max(0.0, elapsed / duration))

                for id in ids {
                    guard self.isControllable(id) else { continue }
                    let interval = self.animationWriteInterval(for: id)
                    let due = t >= 1.0 || lastWriteAt[id].map { now.timeIntervalSince($0) >= interval * 0.90 } ?? true
                    guard due else { continue }

                    let startPercent = starts[id] ?? 0
                    let targetPercent = max(0, min(100, targets[id] ?? startPercent))
                    let normalized = (Double(startPercent) + Double(targetPercent - startPercent) * t) / 100.0
                    let signature = self.animationLevelSignature(for: id, normalized: normalized)
                    guard lastSentLevel[id] != signature else { continue }

                    if self.applyRuntimeBrightnessNormalized(id, normalized: normalized, reason: reason, logPacket: false) {
                        lastSentLevel[id] = signature
                        lastWriteAt[id] = now
                    }
                }

                if t >= 1.0 { break }
                try? await Task.sleep(for: .seconds(timelineTick))
            }

            guard !Task.isCancelled else { return }
            for id in ids {
                let target = max(0, min(100, targets[id] ?? starts[id] ?? 0))
                let sent = await self.applyRuntimeBrightnessWhenReady(
                    id,
                    percent: target,
                    reason: "\(reason) final",
                    persist: true
                )
                if !sent {
                    self.logger.log("AMBIENT FLOW", "Final brightness \(target)% could not be delivered to \(self.pairedDevice(id)?.displayName ?? id.uuidString)")
                }
                self.brightnessTransitionTasks[id] = nil
            }
            self.logger.log("AMBIENT FADE", "Smooth brightness transition complete reason=\(reason)")
        }

        for id in ids { brightnessTransitionTasks[id] = task }
    }

    // MARK: - Packet adapters

    private func ambientTransportCanAcceptWrite(_ id: UUID) -> Bool {
        guard let peripheral = peripheralsByID[id], peripheral.state == .connected,
              let characteristic = writeCharacteristicsByID[id] else { return false }
        if characteristic.properties.contains(.writeWithoutResponse) {
            return peripheral.canSendWriteWithoutResponse
        }
        return characteristic.properties.contains(.write)
    }

    @discardableResult
    private func sendPower(_ id: UUID, on: Bool, reason: String) -> Bool {
        guard let device = pairedDevice(id) else { return false }
        guard ambientTransportCanAcceptWrite(id) else {
            logger.log("AMBIENT FLOW", "Deferred power \(on ? "ON" : "OFF") for \(device.displayName): BLE writeWithoutResponse backpressure/not ready")
            return false
        }
        switch device.protocolKind {
        case .lotusLantern:
            return writeAmbient(
                LotusLanternProtocol.power(on),
                to: id,
                label: "power \(on ? "ON" : "OFF") \(reason)"
            )
        case .bledim2:
            let sequence = nextBLEDIMSequence(for: id)
            return writeAmbient(
                BLEDIM2Protocol.power(on, sequence: sequence),
                to: id,
                label: "BLEDIM2 seq=\(String(format: "%02X", sequence)) power \(on ? "ON" : "OFF") \(reason)"
            )
        }
    }

    @discardableResult
    private func sendColor(_ id: UUID, color: AmbientRGB, reason: String) -> Bool {
        guard let device = pairedDevice(id) else { return false }
        guard ambientTransportCanAcceptWrite(id) else {
            logger.log("AMBIENT FLOW", "Deferred RGB for \(device.displayName): BLE writeWithoutResponse backpressure/not ready")
            return false
        }
        let packet: Data
        let protocolLabel: String
        switch device.protocolKind {
        case .lotusLantern:
            packet = LotusLanternProtocol.color(color)
            protocolLabel = "RGB"
        case .bledim2:
            let sequence = nextBLEDIMSequence(for: id)
            packet = BLEDIM2Protocol.color(color, sequence: sequence)
            protocolLabel = "BLEDIM2 seq=\(String(format: "%02X", sequence)) RGB"
        }
        return writeAmbient(
            packet,
            to: id,
            label: "\(protocolLabel) \(color.red),\(color.green),\(color.blue) \(reason)"
        )
    }

    @discardableResult
    private func sendBrightness(_ id: UUID, percent: Int, reason: String, logPacket: Bool = true) -> Bool {
        guard let device = pairedDevice(id) else { return false }
        guard ambientTransportCanAcceptWrite(id) else {
            // Animation loops deliberately skip this frame and try the newest
            // brightness on a later tick instead of piling stale frames into the
            // CoreBluetooth write-without-response queue.
            return false
        }
        let clamped = max(0, min(100, percent))
        let packet: Data
        let protocolLabel: String
        switch device.protocolKind {
        case .lotusLantern:
            packet = LotusLanternProtocol.brightness(clamped)
            protocolLabel = "brightness"
        case .bledim2:
            let sequence = nextBLEDIMSequence(for: id)
            packet = BLEDIM2Protocol.brightness(clamped, sequence: sequence)
            protocolLabel = "BLEDIM2 seq=\(String(format: "%02X", sequence)) brightness"
        }
        return writeAmbient(
            packet,
            to: id,
            label: "\(protocolLabel) \(clamped)% \(reason)",
            logPacket: logPacket
        )
    }

    /// Animation-only normalized brightness path. BLEDIM2 receives its native
    /// 0...255 value rather than a value first rounded to an integer percent.
    /// Logical 0% remains a minimum-brightness command; it is never translated
    /// into a power-OFF packet.
    @discardableResult
    private func sendBrightnessNormalized(
        _ id: UUID,
        normalized: Double,
        reason: String,
        logPacket: Bool = false
    ) -> Bool {
        guard let device = pairedDevice(id), ambientTransportCanAcceptWrite(id) else { return false }
        let level = max(0.0, min(1.0, normalized))
        let percent = Int((level * 100.0).rounded())
        let packet: Data
        let protocolLabel: String
        switch device.protocolKind {
        case .lotusLantern:
            packet = LotusLanternProtocol.brightness(percent)
            protocolLabel = "brightness"
        case .bledim2:
            let sequence = nextBLEDIMSequence(for: id)
            let raw = UInt8((level * 255.0).rounded())
            packet = BLEDIM2Protocol.brightnessRaw(raw, sequence: sequence)
            protocolLabel = "BLEDIM2 seq=\(String(format: "%02X", sequence)) brightness raw=\(raw)"
        }
        return writeAmbient(
            packet,
            to: id,
            label: "\(protocolLabel) \(percent)% \(reason)",
            logPacket: logPacket
        )
    }

    private func nextBLEDIMSequence(for id: UUID) -> UInt8 {
        var sequence = bledimSequenceByID[id] ?? 0x08
        sequence &+= 1
        if sequence == 0 { sequence = 1 }
        bledimSequenceByID[id] = sequence
        return sequence
    }

    /// Sends runtime brightness without changing the user's preferred steady-state
    /// brightness. Runtime state is advanced only after CoreBluetooth accepted the
    /// write. If a write-without-response peripheral applies backpressure, the
    /// animation keeps its previous known value and retries the newest frame later.
    @discardableResult
    private func applyRuntimeBrightness(
        _ id: UUID,
        percent: Int,
        reason: String,
        persist: Bool = false,
        logPacket: Bool = true
    ) -> Bool {
        let clamped = max(0, min(100, percent))
        guard sendBrightness(id, percent: clamped, reason: reason, logPacket: logPacket) else {
            return false
        }
        if let index = pairedDevices.firstIndex(where: { $0.id == id }) {
            // Fade loops can emit many frames. Keep observable runtime state current,
            // but serialize to UserDefaults only for the confirmed final frame.
            pairedDevices[index].lastAppliedBrightness = clamped
            if persist { persistPairedDevices() }
        }
        return true
    }

    @discardableResult
    private func applyRuntimeBrightnessNormalized(
        _ id: UUID,
        normalized: Double,
        reason: String,
        persist: Bool = false,
        logPacket: Bool = false
    ) -> Bool {
        let level = max(0.0, min(1.0, normalized))
        let percent = Int((level * 100.0).rounded())
        guard sendBrightnessNormalized(id, normalized: level, reason: reason, logPacket: logPacket) else {
            return false
        }
        if let index = pairedDevices.firstIndex(where: { $0.id == id }) {
            pairedDevices[index].lastAppliedBrightness = percent
            if persist { persistPairedDevices() }
        }
        return true
    }

    @discardableResult
    private func writeAmbient(_ data: Data, to id: UUID, label: String, logPacket: Bool = true) -> Bool {
        guard let device = pairedDevice(id) else { return false }
        if device.protocolKind == .lotusLantern && isEncryptedLotusName(device.advertisedName) {
            logger.log("AMBIENT CTRL", "Blocked encrypted ELK-* write for \(device.displayName); encrypted dialect is not enabled")
            return false
        }
        guard let peripheral = peripheralsByID[id], peripheral.state == .connected,
              let characteristic = writeCharacteristicsByID[id] else {
            logger.log("AMBIENT CTRL", "Cannot send \(label) to \(device.displayName): control characteristic unavailable")
            return false
        }

        let writeType: CBCharacteristicWriteType
        if characteristic.properties.contains(.writeWithoutResponse) {
            guard peripheral.canSendWriteWithoutResponse else { return false }
            writeType = .withoutResponse
        } else if characteristic.properties.contains(.write) {
            writeType = .withResponse
        } else {
            logger.log("AMBIENT CTRL", "Control characteristic is not writable for \(device.displayName)")
            return false
        }

        peripheral.writeValue(data, for: characteristic, type: writeType)
        if logPacket {
            logger.log("AMBIENT TX", "\(device.displayName) \(label): \(Self.hex(data))")
        }
        return true
    }

    private func waitForAmbientWriteReady(_ id: UUID, timeout: TimeInterval = 1.5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard !Task.isCancelled else { return false }
            if ambientTransportCanAcceptWrite(id) { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return ambientTransportCanAcceptWrite(id)
    }

    private func sendPowerWhenReady(_ id: UUID, on: Bool, reason: String) async -> Bool {
        let deadline = Date().addingTimeInterval(1.5)
        repeat {
            guard !Task.isCancelled else { return false }
            if ambientTransportCanAcceptWrite(id), sendPower(id, on: on, reason: reason) {
                // Do not burst the next semantic command into the same
                // write-without-response credit. This tiny inter-command settle
                // mirrors a human slider/control interaction and is negligible to UI.
                try? await Task.sleep(for: .milliseconds(50))
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        } while Date() < deadline
        logger.log("AMBIENT FLOW", "Timed out waiting to send power \(on ? "ON" : "OFF") to \(pairedDevice(id)?.displayName ?? id.uuidString)")
        return false
    }

    private func sendColorWhenReady(_ id: UUID, color: AmbientRGB, reason: String) async -> Bool {
        let deadline = Date().addingTimeInterval(1.5)
        repeat {
            guard !Task.isCancelled else { return false }
            if ambientTransportCanAcceptWrite(id), sendColor(id, color: color, reason: reason) {
                try? await Task.sleep(for: .milliseconds(50))
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        } while Date() < deadline
        logger.log("AMBIENT FLOW", "Timed out waiting to send RGB to \(pairedDevice(id)?.displayName ?? id.uuidString)")
        return false
    }

    private func applyRuntimeBrightnessWhenReady(
        _ id: UUID,
        percent: Int,
        reason: String,
        persist: Bool = true
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(1.5)
        repeat {
            guard !Task.isCancelled else { return false }
            if ambientTransportCanAcceptWrite(id),
               applyRuntimeBrightness(id, percent: percent, reason: reason, persist: persist, logPacket: true) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        } while Date() < deadline
        logger.log("AMBIENT FLOW", "Timed out waiting to send final brightness \(percent)% to \(pairedDevice(id)?.displayName ?? id.uuidString)")
        return false
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

    // MARK: - Power-up breath animation

    private func restoreDeviceState(_ id: UUID) {
        guard let device = pairedDevice(id), isControllable(id) else { return }
        restoreTasks[id]?.cancel()
        breathPrepareTasks[id]?.cancel()

        let runtimeTarget: Int
        if vehicleAutomationEnabled, device.role == .door, enginePowerPresent, vehicleStartupCompleted {
            runtimeTarget = doorTargetBrightness(night: vehicleHeadlightsActive)
        } else {
            runtimeTarget = device.brightness
        }

        restoreTasks[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.restoreTasks[id] = nil }

            if device.powerOn {
                // Ordering matters on write-without-response controllers. v90.9
                // could successfully send RGB and then silently drop Power ON and
                // brightness because the BLE buffer was temporarily full.
                guard await self.sendPowerWhenReady(id, on: true, reason: "restore") else { return }
                guard !Task.isCancelled else { return }
                _ = await self.sendColorWhenReady(id, color: device.color, reason: "restore")
                guard !Task.isCancelled else { return }
                _ = await self.applyRuntimeBrightnessWhenReady(
                    id,
                    percent: runtimeTarget,
                    reason: "restore",
                    persist: true
                )
            } else {
                _ = await self.sendPowerWhenReady(id, on: false, reason: "restore")
            }
        }
    }

    private func runStartupAnimationIfNeeded(_ id: UUID, force: Bool = false) {
        if force {
            queuePowerUpBreath(id, force: true)
            return
        }
        if isHeadlightFedDevice(id) {
            scheduleHeadlightConsensusEvaluation(
                reason: "\(pairedDevice(id)?.displayName ?? id.uuidString) GATT ready"
            )

            // v90.10 same-epoch behavior: once this controller already consumed the
            // current physical headlight epoch, a BLE reconnect must restore its
            // normal steady state rather than rejoin/replay the Breath.
            if headlightPowerSessionActive,
               headlightAnimatedEpochByID[id] == headlightPowerEpoch {
                logger.log(
                    "AMBIENT POWER",
                    "Same-epoch headlight reconnect → steady restore: \(pairedDevice(id)?.displayName ?? id.uuidString) epoch=\(headlightPowerEpoch)"
                )
                restoreDeviceState(id)
                return
            }

            if headlightPowerSessionActive {
                tryStartConfirmedHeadlightBreath(reason: "headlight GATT ready")
            } else {
                // During the mixed/settling interval, keep a newly controllable
                // controller at its preferred steady state. The shared Breath is
                // still withheld until BOTH controllers confirm ON and are ready.
                restoreDeviceState(id)
            }
            return
        }
        queuePowerUpBreath(id)
    }

    private func queuePowerUpBreath(_ id: UUID, force: Bool = false) {
        guard let device = pairedDevice(id), isControllable(id) else { return }

        if activeBreathIDs.contains(id) || breathPrepareTasks[id] != nil {
            logger.log("AMBIENT ANIM", "Breath request ignored while already active/preparing: \(device.displayName); initial/return brightness preserved")
            return
        }

        if !force, let role = device.role, role.isHeadlightFed {
            // Headlight-fed lights animate once per physical headlight ON epoch,
            // even when OFF -> ON happens much faster than the old 15-second BLE
            // reconnect heuristic.
            guard headlightPowerSessionActive else {
                restoreDeviceState(id)
                return
            }
            if headlightAnimatedEpochByID[id] == headlightPowerEpoch {
                restoreDeviceState(id)
                return
            }
        } else if !force && animatedConnectionSession.contains(id) {
            restoreDeviceState(id)
            return
        }

        guard device.startupAnimationEnabled, device.powerOn else {
            if let role = device.role, role.isHeadlightFed {
                headlightAnimatedEpochByID[id] = headlightPowerEpoch
            } else {
                animatedConnectionSession.insert(id)
            }
            restoreDeviceState(id)
            return
        }

        cancelBrightnessTransition(for: id)
        restoreTasks[id]?.cancel()
        restoreTasks[id] = nil

        let initialBrightness: Int
        if force {
            initialBrightness = device.runtimeBrightness
        } else if vehicleAutomationEnabled, device.role == .door, enginePowerPresent, vehicleStartupCompleted {
            initialBrightness = doorTargetBrightness(night: vehicleHeadlightsActive)
        } else {
            initialBrightness = device.brightness
        }

        breathPrepareTasks[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.breathPrepareTasks[id] = nil }

            // Critical preparation is serialized and retried instead of being
            // dropped under CoreBluetooth write-without-response backpressure.
            guard await self.sendPowerWhenReady(id, on: true, reason: "power-up breath prepare") else { return }
            guard !Task.isCancelled else { return }
            guard await self.sendColorWhenReady(id, color: device.color, reason: "power-up breath prepare") else { return }
            guard !Task.isCancelled else { return }
            guard await self.applyRuntimeBrightnessWhenReady(
                id,
                percent: initialBrightness,
                reason: "power-up breath baseline",
                persist: false
            ) else { return }
            guard !Task.isCancelled, self.isControllable(id) else { return }

            if !force, let role = device.role, role.isHeadlightFed {
                guard self.headlightPowerSessionActive else { return }
                self.headlightAnimatedEpochByID[id] = self.headlightPowerEpoch
            } else {
                self.animatedConnectionSession.insert(id)
            }

            self.activeBreathIDs.insert(id)
            self.activeBreathStartBrightness[id] = initialBrightness
            self.activeBreathReturnBrightness[id] = initialBrightness

            if self.synchronizedBreathTask != nil {
                self.logger.log("AMBIENT ANIM", "Joined active synchronized breath: \(device.displayName)")
                return
            }

            if self.pendingBreathStartTask == nil {
                self.pendingBreathStartTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Give headlight-fed Dashboard + Center enough time to finish
                    // GATT preparation and enter the same shared animation epoch.
                    // 0.75 s is still short relative to a 1–15 s breath cycle but
                    // materially improves visual synchronization over the old 0.35 s.
                    try? await Task.sleep(for: .seconds(0.75))
                    guard !Task.isCancelled else { return }
                    self.pendingBreathStartTask = nil
                    self.startSynchronizedBreathSession()
                }
            }
        }
    }

    private func startSynchronizedBreathSession() {
        guard synchronizedBreathTask == nil else { return }

        let ready = activeBreathIDs.filter { id in
            guard let device = pairedDevice(id) else { return false }
            return device.startupAnimationEnabled && device.powerOn && isControllable(id)
        }
        guard !ready.isEmpty else {
            activeBreathIDs.removeAll()
            activeBreathStartBrightness.removeAll()
            activeBreathReturnBrightness.removeAll()
            return
        }

        activeBreathIDs = Set(ready)
        let startedAt = Date()
        activeBreathStartedAt = startedAt
        let cycles = max(2, min(5, breathCycles))
        let perCycleDuration = max(1.0, min(15.0, breathDurationSeconds))
        let totalDuration = perCycleDuration * Double(cycles)
        let timelineTick = 0.05

        logger.log(
            "AMBIENT ANIM",
            "Synchronized breath begin lights=\(ready.count) cycles=\(cycles) perCycle=\(String(format: "%.1f", perCycleDuration))s total=\(String(format: "%.1f", totalDuration))s pacing=20Hz/rawBLEDIM"
        )

        synchronizedBreathTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastSentLevel: [UUID: Int] = [:]
            var lastWriteAt: [UUID: Date] = [:]

            while true {
                guard !Task.isCancelled else { return }
                let now = Date()
                let elapsed = now.timeIntervalSince(startedAt)
                let progress = min(1.0, max(0.0, elapsed / totalDuration))
                let ids = Array(self.activeBreathIDs)

                for id in ids {
                    guard self.isControllable(id), let start = self.activeBreathStartBrightness[id] else { continue }
                    let interval = self.animationWriteInterval(for: id)
                    let due = progress >= 1.0 || lastWriteAt[id].map { now.timeIntervalSince($0) >= interval * 0.90 } ?? true
                    guard due else { continue }

                    let returnTarget = self.activeBreathReturnBrightness[id] ?? start
                    let normalized = self.breathBrightnessFraction(
                        start: start,
                        returnTarget: returnTarget,
                        progress: progress,
                        cycles: cycles
                    )
                    let signature = self.animationLevelSignature(for: id, normalized: normalized)
                    guard lastSentLevel[id] != signature else { continue }

                    let maxSignature = self.pairedDevice(id)?.protocolKind == .bledim2 ? 255 : 100
                    let logPacket = signature == 0 || signature == maxSignature
                    if self.applyRuntimeBrightnessNormalized(
                        id,
                        normalized: normalized,
                        reason: "synchronized power-up breath",
                        logPacket: logPacket
                    ) {
                        lastSentLevel[id] = signature
                        lastWriteAt[id] = now
                    }
                }

                if progress >= 1.0 { break }
                try? await Task.sleep(for: .seconds(timelineTick))
            }

            guard !Task.isCancelled else { return }
            let finishedIDs = Array(self.activeBreathIDs)
            for id in finishedIDs {
                guard let start = self.activeBreathStartBrightness[id] else { continue }
                let returnTarget = self.activeBreathReturnBrightness[id] ?? start
                _ = await self.applyRuntimeBrightnessWhenReady(
                    id,
                    percent: returnTarget,
                    reason: "power-up breath final",
                    persist: true
                )
            }

            self.synchronizedBreathTask = nil
            self.activeBreathStartedAt = nil
            self.activeBreathIDs.removeAll()
            self.activeBreathStartBrightness.removeAll()
            self.activeBreathReturnBrightness.removeAll()
            self.logger.log("AMBIENT ANIM", "Synchronized breath complete lights=\(finishedIDs.count) elapsed=\(String(format: "%.2f", Date().timeIntervalSince(startedAt)))s")

            if self.vehicleAutomationEnabled, self.enginePowerPresent, self.vehicleStartupCompleted {
                self.applyCurrentDoorDayNightTarget(reason: "post-breath door target")
            }
        }
    }

    private func breathBrightnessFraction(start: Int, returnTarget: Int, progress: Double, cycles: Int) -> Double {
        let clampedStart = max(0, min(100, start))
        let clampedReturn = max(0, min(100, returnTarget))
        let p = max(0.0, min(1.0, progress))
        if p >= 1.0 { return Double(clampedReturn) / 100.0 }

        let safeCycles = max(1, cycles)
        let cyclePosition = p * Double(safeCycles)
        let cycleIndex = min(safeCycles - 1, Int(floor(cyclePosition)))
        let local = cyclePosition - floor(cyclePosition)
        let leg = min(2, Int(floor(local * 3.0)))
        let legProgress = min(1.0, (local * 3.0) - Double(leg))

        // Match the physical feel of continuously moving the brightness slider:
        // every leg advances linearly through the controller's available brightness
        // levels. The previous half-cosine easing lingered near 0/100 and made the
        // BLEDIM lamps visibly step/stall at the dark end.
        let ramp = legProgress

        let from: Double
        let to: Double
        switch leg {
        case 0:
            from = Double(clampedStart); to = 0
        case 1:
            from = 0; to = 100
        default:
            from = 100
            to = Double(cycleIndex == safeCycles - 1 ? clampedReturn : clampedStart)
        }
        return max(0.0, min(1.0, (from + (to - from) * ramp) / 100.0))
    }

    private func breathBrightness(start: Int, returnTarget: Int, progress: Double, cycles: Int) -> Int {
        Int((breathBrightnessFraction(
            start: start,
            returnTarget: returnTarget,
            progress: progress,
            cycles: cycles
        ) * 100.0).rounded())
    }

    private func removeFromActiveBreath(_ id: UUID) {
        activeBreathIDs.remove(id)
        activeBreathStartBrightness[id] = nil
        activeBreathReturnBrightness[id] = nil
        if activeBreathIDs.isEmpty {
            pendingBreathStartTask?.cancel()
            pendingBreathStartTask = nil
            synchronizedBreathTask?.cancel()
            synchronizedBreathTask = nil
            activeBreathStartedAt = nil
        }
    }

    /// Do not replay the power-up breath for a momentary BLE dropout. A device must
    /// remain disconnected for 15 seconds before the next connection is considered
    /// a genuinely fresh physical power session.
    private func scheduleStartupSessionReset(_ id: UUID) {
        // Dashboard/Center are re-armed by a physical headlight-power epoch, not by
        // elapsed disconnect time. A quick OFF -> ON must be allowed to Breath again.
        if isHeadlightFedDevice(id) {
            sessionResetTasks[id]?.cancel()
            sessionResetTasks[id] = nil
            return
        }
        sessionResetTasks[id]?.cancel()
        sessionResetTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            if self.peripheralsByID[id]?.state != .connected {
                self.animatedConnectionSession.remove(id)
                self.removeFromActiveBreath(id)
                self.logger.log("AMBIENT ANIM", "Power-up animation re-armed after 15s disconnect for \(id)")
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

    private func isHeadlightFedDevice(_ id: UUID) -> Bool {
        pairedDevice(id)?.role?.isHeadlightFed == true
    }

    private func isKnownVehicleAmbientDevice(_ id: UUID) -> Bool {
        pairedDevice(id)?.role != nil
    }

    private enum HeadlightConsensusObservation: String {
        case bothOn
        case bothOff
        case mixed
    }

    /// Positive physical-power evidence is either a live CoreBluetooth connection or
    /// a very recent advertisement/connection observation. The short recent-evidence
    /// allowance bridges connection setup without turning a stale radio event into a
    /// long-lived headlight state.
    private func headlightPowerEvidence(_ id: UUID, now: Date = Date()) -> Bool {
        if peripheralsByID[id]?.state == .connected { return true }
        if let seen = lastSeenByID[id],
           now.timeIntervalSince(seen) <= headlightRecentEvidenceSeconds {
            return true
        }
        return false
    }

    private func currentHeadlightConsensus(now: Date = Date()) -> HeadlightConsensusObservation {
        guard let dashboardID = deviceID(for: .dashboard),
              let centerID = deviceID(for: .centerConsole) else {
            return .mixed
        }

        let dashboardOn = headlightPowerEvidence(dashboardID, now: now)
        let centerOn = headlightPowerEvidence(centerID, now: now)
        if dashboardOn && centerOn { return .bothOn }
        if !dashboardOn && !centerOn { return .bothOff }
        return .mixed
    }

    /// v90.14 consensus gate. Every Dashboard/Center presence or disconnect event
    /// restarts one short stability timer. Only BOTH ON or BOTH OFF can commit a
    /// vehicle headlight edge. A mixed state is explicitly transitional/unknown and
    /// preserves the previously confirmed state.
    private func scheduleHeadlightConsensusEvaluation(reason: String) {
        headlightConsensusTask?.cancel()
        headlightConsensusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.headlightConsensusStabilitySeconds))
            guard !Task.isCancelled else { return }
            self.headlightConsensusTask = nil

            let observation = self.currentHeadlightConsensus()
            switch observation {
            case .bothOn:
                guard !self.headlightPowerSessionActive else {
                    self.tryStartConfirmedHeadlightBreath(reason: "both controllers stable ON; \(reason)")
                    return
                }
                self.commitConfirmedHeadlightPower(true, reason: "both Center + Dashboard stable ON; \(reason)")
            case .bothOff:
                guard self.headlightPowerSessionActive else { return }
                self.commitConfirmedHeadlightPower(false, reason: "both Center + Dashboard stable OFF; \(reason)")
            case .mixed:
                self.logger.log(
                    "AMBIENT POWER",
                    "Headlight consensus mixed after stability window; preserving confirmed \(self.headlightPowerSessionActive ? "ON" : "OFF") state (\(reason))"
                )
            }
        }
    }

    private func commitConfirmedHeadlightPower(_ on: Bool, reason: String) {
        guard headlightPowerSessionActive != on else { return }
        headlightPowerSessionActive = on
        headlightStateGeneration &+= 1

        let headlightIDs = roleIDs([.dashboard, .centerConsole])
        if on {
            headlightPowerEpoch &+= 1
            if headlightPowerEpoch <= 0 { headlightPowerEpoch = 1 }
            for id in headlightIDs {
                animatedConnectionSession.remove(id)
            }
            logger.log(
                "AMBIENT POWER",
                "Consensus headlight ON epoch=\(headlightPowerEpoch) generation=\(headlightStateGeneration) (\(reason))"
            )
            if hudBrightnessTriggerEnabled, bluetooth.state == .connected {
                bluetooth.enqueue(
                    HudCommands.autoBrightness(true),
                    label: "Headlight consensus → Auto brightness ON"
                )
                lastHUDReassertAt = Date()
            }

            if vehicleAutomationEnabled, enginePowerPresent, vehicleStartupCompleted {
                vehicleHeadlightsActive = true
                previousHeadlightPowerPresent = true
                applyCurrentDoorDayNightTarget(reason: "consensus headlight ON → night Door brightness")
                logger.log(
                    "AMBIENT AUTO",
                    "Consensus headlight ON while engine ON: night Door target=\(doorTargetBrightness(night: true))%"
                )
            }

            tryStartConfirmedHeadlightBreath(reason: reason)
        } else {
            for id in headlightIDs {
                breathPrepareTasks[id]?.cancel()
                breathPrepareTasks[id] = nil
                restoreTasks[id]?.cancel()
                restoreTasks[id] = nil
                removeFromActiveBreath(id)
            }

            if let activeID = overspeedWarningActiveID,
               pairedDevice(activeID)?.role == .dashboard {
                cancelOverspeedWarning(
                    restoreIfPossible: false,
                    reason: "confirmed headlight OFF during Dashboard warning"
                )
            }

            logger.log(
                "AMBIENT POWER",
                "Consensus headlight OFF generation=\(headlightStateGeneration) (\(reason)); headlight animation work cancelled"
            )
            if hudBrightnessTriggerEnabled, bluetooth.state == .connected {
                bluetooth.enqueue(
                    HudCommands.autoBrightness(false),
                    label: "Headlight consensus → Auto brightness OFF"
                )
            }

            if vehicleAutomationEnabled, enginePowerPresent, vehicleStartupCompleted {
                vehicleHeadlightsActive = false
                previousHeadlightPowerPresent = false
                applyCurrentDoorDayNightTarget(reason: "consensus headlight OFF → day Door brightness")
                logger.log(
                    "AMBIENT AUTO",
                    "Consensus headlight OFF while engine ON: day Door target=\(doorTargetBrightness(night: false))%"
                )
            }
        }
    }

    /// Do not let the first controller that becomes GATT-ready start a partial
    /// headlight animation. Once physical headlight power is confirmed ON, wait
    /// until both Center and Dashboard are controllable. Then queue both against
    /// the same v90.10 shared Breath timeline.
    private func tryStartConfirmedHeadlightBreath(reason: String) {
        guard headlightPowerSessionActive,
              let dashboardID = deviceID(for: .dashboard),
              let centerID = deviceID(for: .centerConsole),
              isControllable(dashboardID),
              isControllable(centerID) else { return }

        let ids = [dashboardID, centerID]
        let pending = ids.filter { id in
            guard let device = pairedDevice(id), device.powerOn else { return false }
            return headlightAnimatedEpochByID[id] != headlightPowerEpoch
        }
        guard !pending.isEmpty else { return }

        logger.log(
            "AMBIENT ANIM",
            "Consensus headlight animation admitted epoch=\(headlightPowerEpoch) ready=2 reason=\(reason)"
        )
        for id in pending {
            queuePowerUpBreath(id)
        }
    }

    /// Record positive physical-power evidence for either headlight-fed controller.
    /// Positive evidence alone never flips the headlight state; the stable two-light
    /// consensus does.
    private func noteHeadlightPowerSeen(_ id: UUID, reason: String) {
        guard isHeadlightFedDevice(id) else { return }
        scheduleHeadlightConsensusEvaluation(
            reason: "\(pairedDevice(id)?.displayName ?? id.uuidString) positive evidence via \(reason)"
        )
        if headlightPowerSessionActive {
            tryStartConfirmedHeadlightBreath(reason: reason)
        }
    }

    /// Compatibility call used by disconnect paths. OFF is no longer inferred from
    /// one controller. The same consensus evaluator requires both to be absent.
    private func scheduleHeadlightPowerOffEvaluation(reason: String) {
        scheduleHeadlightConsensusEvaluation(reason: reason)
    }

    private func headlightPowerPresent() -> Bool {
        // v90.10 uses a physical headlight-power epoch rather than the old 8-second
        // logical-presence window. Positive evidence is immediate; OFF requires the
        // short dual-controller debounce in scheduleHeadlightPowerOffEvaluation.
        headlightPowerSessionActive
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
        guard let dashboardID = deviceID(for: .dashboard),
              let centerID = deviceID(for: .centerConsole) else { return false }

        func poweredAfterEngineOn(_ id: UUID) -> Bool {
            if peripheralsByID[id]?.state == .connected { return true }
            guard let seen = lastSeenByID[id], seen >= engineOnAt else { return false }
            return now.timeIntervalSince(seen) <= 2.0
        }

        // Startup uses the same safety rule as runtime: BOTH headlight-fed
        // controllers must still show power after the courtesy-light settle.
        return poweredAfterEngineOn(dashboardID) && poweredAfterEngineOn(centerID)
    }

    private func doorTargetBrightness(night: Bool) -> Int {
        max(0, min(100, night ? doorNightBrightness : doorDayBrightness))
    }

    var doorBrightnessModeStatus: String {
        if !vehicleAutomationEnabled {
            return "Door day/night automation off • day \(doorDayBrightness)% • night \(doorNightBrightness)%"
        }
        guard enginePowerPresent else {
            return "Engine off • Door brightness is not changed"
        }
        guard vehicleStartupCompleted else {
            return "Engine on • waiting briefly for courtesy headlights to settle"
        }
        let target = doorTargetBrightness(night: vehicleHeadlightsActive)
        return "\(vehicleHeadlightsActive ? "Night" : "Day") • Door target \(target)%"
    }

    private func applyDoorTargetAfterSettingChange(changedNightTarget: Bool) {
        guard vehicleAutomationEnabled,
              enabled,
              enginePowerPresent,
              vehicleSessionActive,
              vehicleStartupCompleted else { return }

        let night = headlightPowerPresent()
        guard night == changedNightTarget else { return }
        let target = doorTargetBrightness(night: night)
        if let doorID = deviceID(for: .door), activeBreathIDs.contains(doorID) {
            activeBreathReturnBrightness[doorID] = target
            logger.log("AMBIENT ANIM", "Door breath final target updated to \(target)% by \(night ? "night" : "day") setting")
            return
        }
        transitionDoorBrightness(
            to: target,
            over: brightnessTransitionSeconds,
            reason: night ? "night target changed" : "day target changed"
        )
    }

    private func resetVehicleAutomationRuntime(reason: String) {
        startupClassificationTask?.cancel()
        startupClassificationTask = nil
        engineOffConfirmationTask?.cancel()
        engineOffConfirmationTask = nil
        hudOutageBeganAt = nil
        if !enginePowerPresent { enginePowerBecamePresentAt = nil }
        vehicleSessionActive = false
        vehicleStartupCompleted = false
        vehicleHeadlightsActive = false
        previousHeadlightPowerPresent = false
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
            vehicleSessionActive = false
            vehicleStartupCompleted = false
            vehicleHeadlightsActive = false
            previousHeadlightPowerPresent = false
                        vehicleAutomationStatus = "Engine power ON • waiting briefly for courtesy headlights to settle"
            logger.log("AMBIENT ENGINE", "Engine-switched power ON via \(source); starting simplified Door day/night settle window")
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
        startupClassificationTask?.cancel()
        startupClassificationTask = nil
        vehicleSessionActive = false
        vehicleStartupCompleted = false
        vehicleHeadlightsActive = false
        previousHeadlightPowerPresent = false
        enginePowerBecamePresentAt = nil
        logger.log(
            "AMBIENT ENGINE",
            "Engine power OFF confirmed; v90.8 leaves all ambient lights at their current brightness and waits for the vehicle to remove physical power"
        )
        if vehicleAutomationEnabled {
            vehicleAutomationStatus = "Engine OFF • lights unchanged until vehicle power changes"
        }
    }

    /// Simplified v90.8 vehicle-aware behavior. Engine state only gates Door
    /// day/night brightness; it no longer owns startup/shutdown animations or
    /// suppresses courtesy lights. Power-up animation is handled independently by
    /// each light's Animation toggle and the shared synchronized breath timeline.
    private func evaluateVehicleLightingAutomation() {
        guard vehicleAutomationEnabled, enabled else { return }

        guard enginePowerPresent else {
            vehicleSessionActive = false
            vehicleStartupCompleted = false
            vehicleHeadlightsActive = false
            previousHeadlightPowerPresent = false
            vehicleAutomationStatus = "Engine OFF • ambient lights left unchanged until vehicle power changes"
            return
        }

        if !vehicleSessionActive {
            vehicleSessionActive = true
        }

        // Keep the existing hidden post-engine settling delay so entry courtesy
        // headlights do not briefly force the Door to the night target in daylight.
        if !vehicleStartupCompleted {
            if startupClassificationTask == nil {
                beginVehicleStartupClassification()
            }
            return
        }

        let headlightsPresent = headlightPowerPresent()
        if headlightsPresent != previousHeadlightPowerPresent {
            vehicleHeadlightsActive = headlightsPresent
            applyCurrentDoorDayNightTarget(
                reason: headlightsPresent
                    ? "headlight-fed lights on → night Door brightness"
                    : "headlight-fed lights off → day Door brightness"
            )
            logger.log(
                "AMBIENT AUTO",
                "Headlight state changed while engine ON: \(headlightsPresent ? "night" : "day") Door target=\(doorTargetBrightness(night: headlightsPresent))%"
            )
        }
        previousHeadlightPowerPresent = headlightsPresent
        vehicleAutomationStatus = headlightsPresent
            ? "Engine ON • night • Door target \(doorNightBrightness)%"
            : "Engine ON • day • Door target \(doorDayBrightness)%"
    }

    private func beginVehicleStartupClassification() {
        vehicleSessionActive = true
        vehicleStartupCompleted = false

        let now = Date()
        let engineOnAt = enginePowerBecamePresentAt ?? now
        let elapsedSinceEngineOn = max(0, now.timeIntervalSince(engineOnAt))
        let remainingSettle = max(0.5, startupClassificationSeconds - elapsedSinceEngineOn)

        vehicleAutomationStatus = "Engine ON • waiting briefly for courtesy headlights to settle"
        logger.log(
            "AMBIENT AUTO",
            "Simplified day/night settle begin remaining=\(String(format: "%.1f", remainingSettle))s; no light brightness is changed during the settle window"
        )

        startupClassificationTask?.cancel()
        startupClassificationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(remainingSettle))
            guard !Task.isCancelled, self.vehicleAutomationEnabled, self.enginePowerPresent else { return }
            self.startupClassificationTask = nil
            self.finishVehicleStartupClassification()
        }
    }

    private func finishVehicleStartupClassification() {
        let night = startupHeadlightPowerPresent()
        if night && !headlightPowerSessionActive {
            commitConfirmedHeadlightPower(true, reason: "startup settle confirmed both headlight controllers ON")
        } else if !night && headlightPowerSessionActive {
            commitConfirmedHeadlightPower(false, reason: "startup settle confirmed both headlight controllers OFF")
        }
        vehicleHeadlightsActive = night
        previousHeadlightPowerPresent = night
        vehicleStartupCompleted = true
        vehicleAutomationStatus = night
            ? "Engine ON • night • Door target \(doorNightBrightness)%"
            : "Engine ON • day • Door target \(doorDayBrightness)%"
        logger.log(
            "AMBIENT AUTO",
            "Simplified startup classification complete: \(night ? "night" : "day"); applying Door target only"
        )
        applyCurrentDoorDayNightTarget(reason: night ? "startup night Door target" : "startup day Door target")
    }

    private func applyCurrentDoorDayNightTarget(reason: String) {
        guard vehicleAutomationEnabled, enginePowerPresent, vehicleStartupCompleted,
              let doorID = deviceID(for: .door),
              isLogicallyPowered(doorID), isControllable(doorID),
              let door = pairedDevice(doorID) else { return }

        let target = doorTargetBrightness(night: vehicleHeadlightsActive)
        if activeBreathIDs.contains(doorID) {
            activeBreathReturnBrightness[doorID] = target
            logger.log("AMBIENT ANIM", "Door breath final target updated to \(target)% reason=\(reason)")
            return
        }
        if door.runtimeBrightness == target {
            applyRuntimeBrightness(doorID, percent: target, reason: "\(reason) already at target", persist: true)
            return
        }
        // Day/night automation changes brightness only. Re-sending Power ON + RGB
        // before every fade consumed BLEDIM's write-without-response credits and
        // was the main reason v90.9 could start a fade with its critical follow-up
        // writes deferred. Color and power are restored reliably on connection.
        transitionBrightness(
            ids: [doorID],
            targets: [doorID: target],
            over: brightnessTransitionSeconds,
            reason: reason
        )
    }

    private func transitionDoorBrightness(to targetPercent: Int, over seconds: Double, reason: String) {
        guard let doorID = deviceID(for: .door), isLogicallyPowered(doorID), isControllable(doorID) else { return }
        transitionBrightness(
            ids: [doorID],
            targets: [doorID: max(0, min(100, targetPercent))],
            over: seconds,
            reason: reason
        )
    }

    /// Preview the one supported power-up animation using every enabled, currently
    /// controllable light. They are queued into the same synchronized breath session.
    func previewEnabledBreathNow() {
        for device in pairedDevices where device.startupAnimationEnabled && device.powerOn && isControllable(device.id) {
            animatedConnectionSession.remove(device.id)
            queuePowerUpBreath(device.id, force: true)
        }
    }


    // MARK: - Finite configurable-color overspeed warning

    /// Called by the GPS/OSM speed engine. A warning is generated only on the
    /// FALSE -> TRUE edge of `gpsSpeed > postedLimit + offset`. If the speed-limit
    /// sign is unavailable, warning logic is disabled and no stale limit is used.
    func updateOverspeedWarning(
        gpsSpeedMph: Int,
        speedLimitMph: Int,
        limitAvailable: Bool
    ) {
        guard overspeedWarningEnabled else {
            overspeedCrossingBaselineValid = false
            overspeedAboveThreshold = false
            overspeedLastLimitAvailable = false
            overspeedWarningStatus = "Disabled"
            return
        }

        let available = limitAvailable && speedLimitMph > 0
        if !available {
            overspeedLastLimitAvailable = false
            overspeedCrossingBaselineValid = false
            overspeedAboveThreshold = false
            if overspeedWarningTask != nil {
                cancelOverspeedWarning(
                    restoreIfPossible: true,
                    reason: "speed-limit sign unavailable"
                )
            }
            overspeedWarningStatus = "Armed — waiting for a valid speed-limit sign"
            return
        }

        let offset = max(0, min(20, overspeedWarningOffsetMph))
        let threshold = speedLimitMph + offset
        let above = gpsSpeedMph > threshold

        if !overspeedCrossingBaselineValid || !overspeedLastLimitAvailable {
            overspeedCrossingBaselineValid = true
            overspeedLastLimitAvailable = true
            overspeedAboveThreshold = above
            overspeedWarningStatus = above
                ? "Above \(threshold) mph — fall below and recross to warn"
                : "Armed • trigger > \(threshold) mph"
            return
        }

        overspeedLastLimitAvailable = true
        let crossedUp = above && !overspeedAboveThreshold
        overspeedAboveThreshold = above

        if crossedUp {
            triggerOverspeedWarning(
                gpsSpeedMph: gpsSpeedMph,
                speedLimitMph: speedLimitMph,
                thresholdMph: threshold
            )
        } else if overspeedWarningTask == nil {
            overspeedWarningStatus = above
                ? "Above \(threshold) mph — waiting to fall below and recross"
                : "Armed • trigger > \(threshold) mph"
        }
    }

    private func triggerOverspeedWarning(
        gpsSpeedMph: Int,
        speedLimitMph: Int,
        thresholdMph: Int
    ) {
        guard overspeedWarningTask == nil else {
            logger.log("AMBIENT WARN", "Overspeed recross ignored while finite warning is already active")
            return
        }

        let role = overspeedWarningLight.role
        guard let id = deviceID(for: role),
              let device = pairedDevice(id),
              device.powerOn,
              isControllable(id) else {
            overspeedWarningStatus = "Crossed threshold, but selected warning light is unavailable"
            logger.log("AMBIENT WARN", "Overspeed crossing skipped: selected \(overspeedWarningLight.rawValue) light unavailable")
            return
        }

        if role == .dashboard, !headlightPowerSessionActive {
            overspeedWarningStatus = "Crossed threshold in daylight — Dashboard warning skipped"
            logger.log("AMBIENT WARN", "Overspeed crossing skipped: Dashboard has no confirmed headlight power")
            return
        }

        if let last = overspeedLastWarningTriggeredAt {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < overspeedWarningCooldownSeconds {
                let remaining = max(1, Int(ceil(overspeedWarningCooldownSeconds - elapsed)))
                overspeedWarningStatus = "Cooldown • \(remaining)s until another warning is allowed"
                logger.log("AMBIENT WARN", "Overspeed recross suppressed by 60s cooldown remaining=\(remaining)s")
                return
            }
        }
        overspeedLastWarningTriggeredAt = Date()

        overspeedRestoreTask?.cancel()
        overspeedRestoreTask = nil
        overspeedWarningGeneration &+= 1
        let generation = overspeedWarningGeneration
        let capturedHeadlightGeneration = role == .dashboard ? headlightStateGeneration : nil
        overspeedWarningActiveID = id

        cancelBrightnessTransition(for: id)
        breathPrepareTasks[id]?.cancel()
        breathPrepareTasks[id] = nil
        restoreTasks[id]?.cancel()
        restoreTasks[id] = nil
        removeFromActiveBreath(id)

        let highPercent = max(10, min(100, overspeedWarningBrightness))
        let cycles = max(2, min(3, overspeedWarningPulseCount))
        let configuredCycleDuration = max(0.0, min(5.0, overspeedWarningPulseDurationSeconds))
        let cycleDuration = max(0.05, configuredCycleDuration)
        let warningColor = overspeedWarningColor

        overspeedWarningStatus = "Warning • \(gpsSpeedMph) > \(speedLimitMph) + \(overspeedWarningOffsetMph) mph"
        logger.log(
            "AMBIENT WARN",
            "Overspeed crossing GPS=\(gpsSpeedMph) limit=\(speedLimitMph) threshold=\(thresholdMph) light=\(overspeedWarningLight.rawValue) pulses=\(cycles) brightness=\(highPercent)% color=\(warningColor.red),\(warningColor.green),\(warningColor.blue) cooldown=60s"
        )

        overspeedWarningTask = Task { @MainActor [weak self] in
            guard let self else { return }

            @MainActor func stillValid() -> Bool {
                guard !Task.isCancelled,
                      generation == self.overspeedWarningGeneration,
                      self.overspeedWarningActiveID == id,
                      self.isControllable(id) else { return false }
                if role == .dashboard {
                    guard self.headlightPowerSessionActive,
                          self.headlightStateGeneration == capturedHeadlightGeneration else { return false }
                }
                return true
            }

            guard stillValid() else {
                self.abortOverspeedWarningTask(id, generation: generation, reason: "invalid before prepare")
                return
            }
            guard await self.sendPowerWhenReady(id, on: true, reason: "overspeed warning prepare") else {
                self.abortOverspeedWarningTask(id, generation: generation, reason: "Power ON prepare failed")
                return
            }
            guard stillValid() else {
                self.abortOverspeedWarningTask(id, generation: generation, reason: "invalid after Power ON")
                return
            }
            guard await self.sendColorWhenReady(id, color: warningColor, reason: "overspeed warning color") else {
                self.abortOverspeedWarningTask(id, generation: generation, reason: "warning RGB prepare failed")
                return
            }
            guard stillValid() else {
                self.abortOverspeedWarningTask(id, generation: generation, reason: "invalid after warning RGB")
                return
            }
            guard await self.applyRuntimeBrightnessWhenReady(
                id,
                percent: highPercent,
                reason: "overspeed warning high baseline",
                persist: false
            ) else {
                self.abortOverspeedWarningTask(id, generation: generation, reason: "high baseline failed")
                return
            }

            // Finite high -> low -> high color pulses. 0% here is a brightness
            // command only; no Power OFF packet is ever sent by the warning.
            for pulse in 0..<cycles {
                let startedAt = Date()
                while true {
                    guard stillValid() else {
                        self.abortOverspeedWarningTask(id, generation: generation, reason: "animation ownership lost")
                        return
                    }
                    let local = min(1.0, Date().timeIntervalSince(startedAt) / cycleDuration)
                    let normalizedHigh = Double(highPercent) / 100.0
                    let normalized: Double
                    if local < 0.5 {
                        normalized = normalizedHigh * (1.0 - local / 0.5)
                    } else {
                        normalized = normalizedHigh * ((local - 0.5) / 0.5)
                    }
                    _ = self.applyRuntimeBrightnessNormalized(
                        id,
                        normalized: normalized,
                        reason: "overspeed color pulse \(pulse + 1)/\(cycles)",
                        logPacket: false
                    )
                    if local >= 1.0 { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }

            guard stillValid() else {
                self.abortOverspeedWarningTask(id, generation: generation, reason: "invalid before finite-warning restore")
                return
            }
            self.overspeedWarningTask = nil
            self.overspeedWarningActiveID = nil
            await self.restoreAfterOverspeedWarning(id, generation: generation, reason: "finite warning complete")
            guard generation == self.overspeedWarningGeneration else { return }
            self.overspeedWarningStatus = self.overspeedAboveThreshold
                ? "Warning complete — fall below and recross to warn again"
                : "Armed • waiting for next recross"
        }
    }

    private func abortOverspeedWarningTask(
        _ id: UUID,
        generation: Int,
        reason: String
    ) {
        guard generation == overspeedWarningGeneration,
              overspeedWarningActiveID == id else { return }
        overspeedWarningTask = nil
        overspeedWarningActiveID = nil
        logger.log("AMBIENT WARN", "Overspeed warning aborted safely: \(reason)")

        overspeedRestoreTask?.cancel()
        overspeedRestoreTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.restoreAfterOverspeedWarning(id, generation: generation, reason: "aborted: \(reason)")
            guard generation == self.overspeedWarningGeneration else { return }
            self.overspeedRestoreTask = nil
            self.overspeedWarningStatus = self.overspeedAboveThreshold
                ? "Warning interrupted — fall below and recross to warn again"
                : "Armed • waiting for next recross"
        }
    }

    private func cancelOverspeedWarning(restoreIfPossible: Bool, reason: String) {
        let id = overspeedWarningActiveID
        overspeedWarningGeneration &+= 1
        let generation = overspeedWarningGeneration
        overspeedWarningTask?.cancel()
        overspeedWarningTask = nil
        overspeedWarningActiveID = nil
        overspeedRestoreTask?.cancel()
        overspeedRestoreTask = nil
        logger.log("AMBIENT WARN", "Overspeed warning cancelled: \(reason)")

        guard restoreIfPossible, let id else { return }
        overspeedRestoreTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.restoreAfterOverspeedWarning(id, generation: generation, reason: reason)
            if generation == self.overspeedWarningGeneration {
                self.overspeedRestoreTask = nil
            }
        }
    }

    private func steadyBrightnessAfterWarning(for id: UUID) -> Int {
        guard let device = pairedDevice(id) else { return 100 }
        if device.role == .door,
           vehicleAutomationEnabled,
           enginePowerPresent,
           vehicleStartupCompleted {
            return doorTargetBrightness(night: vehicleHeadlightsActive)
        }
        return device.brightness
    }

    /// Restore exactly one v90.10 reliable steady-state sequence after a warning.
    /// Do not add the v90.13 repeated safeguard rounds; the baseline transport's
    /// send-when-ready path is retained intentionally.
    private func restoreAfterOverspeedWarning(_ id: UUID, generation: Int, reason: String) async {
        guard generation == overspeedWarningGeneration,
              overspeedWarningActiveID == nil,
              let device = pairedDevice(id),
              device.powerOn,
              isControllable(id) else { return }

        if device.role == .dashboard, !headlightPowerSessionActive {
            logger.log("AMBIENT WARN", "Dashboard restore deferred because confirmed headlight power is OFF")
            return
        }

        let target = steadyBrightnessAfterWarning(for: id)
        guard await sendPowerWhenReady(id, on: true, reason: "overspeed restore \(reason)") else { return }
        guard generation == overspeedWarningGeneration, !Task.isCancelled else { return }
        guard await sendColorWhenReady(id, color: device.color, reason: "overspeed restore \(reason)") else { return }
        guard generation == overspeedWarningGeneration, !Task.isCancelled else { return }
        _ = await applyRuntimeBrightnessWhenReady(
            id,
            percent: target,
            reason: "overspeed restore \(reason)",
            persist: true
        )
    }

    // MARK: - Connection management

    private func discoverServicesIfNeeded(
        _ peripheral: CBPeripheral,
        force: Bool = false,
        reason: String
    ) {
        let id = peripheral.identifier
        guard peripheral.state == .connected, pairedDevice(id) != nil else { return }

        if !force, writeCharacteristicsByID[id] != nil {
            return
        }

        let now = Date()
        if !force, let last = lastServiceDiscoveryRequestByID[id],
           now.timeIntervalSince(last) < serviceDiscoveryRetrySeconds {
            return
        }

        lastServiceDiscoveryRequestByID[id] = now
        peripheral.discoverServices(nil)
        logger.log("AMBIENT GATT", "Service discovery requested \(id) reason=\(reason)")
    }

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
                discoverServicesIfNeeded(peripheral, reason: "connected maintenance")
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

        // v90.14: tracked Center presence remains useful for UI/status and as
        // one half of headlight-power evidence, but it no longer changes the HUD
        // brightness mode by itself. The stable Center + Dashboard consensus owns
        // the shared headlight edge.
    }

    private func markAbsent(reason: String) {
        guard lightPresent else { return }
        lightPresent = false
        status = "\(targetName) absent"
        logger.log(
            "AMBIENT",
            "\(targetName) became absent via \(reason); reevaluating two-light headlight consensus"
        )
        if let trackedID = trackedPeripheral?.identifier, isHeadlightFedDevice(trackedID) {
            scheduleHeadlightPowerOffEvaluation(reason: "tracked Center became absent via \(reason)")
        }
        // v90.14: a Center-only disappearance is transitional evidence, not
        // a confirmed headlight-OFF edge. Consensus will change HUD auto brightness
        // only after both Center and Dashboard are stably absent.
    }

    func rehydrateHUDState() {
        guard enabled, hudBrightnessTriggerEnabled, bluetooth.state == .connected else { return }

        let connectedPresence = trackedPeripheral?.state == .connected
        let recentAdvertisement =
            Date().timeIntervalSince(lastSeen) <=
            Double(max(1, absenceTimeoutSeconds) * absenceConfirmationWindows)
        let shouldEnable = headlightPowerSessionActive

        bluetooth.enqueue(
            HudCommands.autoBrightness(shouldEnable),
            label: "HUD rehydrate → consensus auto brightness \(shouldEnable ? "ON" : "OFF")"
        )

        logger.log(
            "AMBIENT SESSION",
            "Rehydrated brightness consensus=\(shouldEnable) centerConnected=\(connectedPresence) centerRecentAdvertisement=\(recentAdvertisement)"
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
            self.noteHeadlightPowerSeen(id, reason: "advertisement")

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
            self.noteHeadlightPowerSeen(id, reason: "didConnect")

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

            if let device = self.pairedDevice(id) {
                self.controllerStatus = "Connected to ambient light; discovering GATT"
                self.lastServiceDiscoveryRequestByID[id] = nil
                if device.protocolKind == .bledim2 {
                    // The official app restarts its one-byte sequence on a new BLE
                    // connection. Keep each physical BLEDIM controller independent.
                    self.bledimSequenceByID[id] = 0x08
                }
                self.discoverServicesIfNeeded(peripheral, force: true, reason: "didConnect")
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
            self.lastServiceDiscoveryRequestByID[id] = nil
            self.lastBLEDIMNotifyLogAtByID[id] = nil
            self.animationTasks[id]?.cancel()
            self.animationTasks[id] = nil
            self.cancelBrightnessTransition(for: id)
            self.breathPrepareTasks[id]?.cancel()
            self.breathPrepareTasks[id] = nil
            self.restoreTasks[id]?.cancel()
            self.restoreTasks[id] = nil
            self.removeFromActiveBreath(id)
            if self.overspeedWarningActiveID == id {
                self.cancelOverspeedWarning(
                    restoreIfPossible: false,
                    reason: "warning light BLE/physical power disconnected"
                )
            }
            if self.isHeadlightFedDevice(id) {
                self.scheduleHeadlightPowerOffEvaluation(reason: "BLE disconnect of \(self.pairedDevice(id)?.displayName ?? id.uuidString)")
            }

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
                    self.controllerStatus = "\(device.displayName) BLEDIM2 FFF1 control ready"
                    self.logger.log(
                        "AMBIENT CTRL",
                        "BLEDIM2 FFF0/FFF1 control ready for \(device.displayName); using official-iOS-capture 55 AA protocol"
                    )
                } else {
                    self.controllerStatus = "\(device.displayName) control ready"
                    self.logger.log("AMBIENT CTRL", "Lotus Lantern FFF0/FFF3 verified control ready for \(device.displayName)")
                }
                self.runStartupAnimationIfNeeded(id)
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
            let id = peripheral.identifier
            if self.pairedDevice(id)?.protocolKind == .bledim2 {
                self.recordBLEDIMDiagnosticValue(
                    peripheralID: id,
                    characteristic: characteristic,
                    value: value
                )

                // FFF1 commonly notifies ten FF bytes for control traffic. Keep the
                // diagnostic state current but only write that repetitive ACK/state
                // pattern to disk once per second per controller.
                let uuid = characteristic.uuid.uuidString.uppercased()
                if self.isBLEDIMWriteCharacteristic(characteristic.uuid),
                   !value.isEmpty, value.allSatisfy({ $0 == 0xFF }) {
                    let now = Date()
                    if let last = self.lastBLEDIMNotifyLogAtByID[id], now.timeIntervalSince(last) < 1.0 {
                        return
                    }
                    self.lastBLEDIMNotifyLogAtByID[id] = now
                    self.logger.log("AMBIENT RX", "\(id) char=\(uuid): FF… (repetitive BLEDIM2 notification, rate-limited)")
                    return
                }
            }
            self.logger.log("AMBIENT RX", "\(id) char=\(characteristic.uuid.uuidString): \(Self.hex(value))")
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
                   let trackedID = self.trackedPeripheral?.identifier,
                   !self.isKnownVehicleAmbientDevice(trackedID),
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

                // Never cancel a pending connection merely because one of the
                // three known vehicle lights is physically unpowered. CoreBluetooth
                // can leave that connect request pending and complete it immediately
                // when vehicle power returns. The old six-second cancel/reconnect
                // loop created hundreds of artificial disconnects in the field log.
                // Keep the stall guard only for unassigned/diagnostic peripherals.
                for (id, started) in self.connectionStartedByID {
                    guard !self.isKnownVehicleAmbientDevice(id),
                          Date().timeIntervalSince(started) > 6,
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

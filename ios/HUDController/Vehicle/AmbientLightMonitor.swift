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
                vehicleAutomationStatus = "Door day/night automation disabled"
                logger.log("AMBIENT AUTO", "Door day/night automation disabled; Center-driven HUD brightness and per-light power-on animation remain active")
            }
        }
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

    /// v90.8 shared manual/group transition profile. v90.18 intentionally keeps
    /// automatic Door day/night response on a separate, faster 1.0-second fade so
    /// it follows the Center/BLEDOM power edge promptly without becoming abrupt.
    var brightnessTransitionSeconds: Double {
        didSet { UserDefaults.standard.set(max(1.0, min(15.0, brightnessTransitionSeconds)), forKey: "HUD.Ambient.v90_8.transitionDuration") }
    }

    private let automaticDoorDayNightTransitionSeconds: TimeInterval = 1.0

    /// One global power-up animation profile keeps multiple lights on a common timebase.
    var breathCycles: Int {
        didSet { UserDefaults.standard.set(max(2, min(5, breathCycles)), forKey: "HUD.Ambient.v90_8.breathCycles") }
    }
    var breathDurationSeconds: Double {
        didSet { UserDefaults.standard.set(max(1.0, min(15.0, breathDurationSeconds)), forKey: "HUD.Ambient.v90_8.breathDuration") }
    }

    /// v90.18: synchronization is optional. OFF remains the robust default. ON
    /// forms a power-on cohort from controllers that physically/GATT-appear near
    /// each other, then waits for their individual boot preparation before issuing
    /// one common Breath T0. Late/unready members still get a complete independent
    /// Breath rather than joining a running waveform.
    var synchronizePowerOnBreathEnabled: Bool {
        didSet {
            UserDefaults.standard.set(synchronizePowerOnBreathEnabled, forKey: "HUD.Ambient.v90_17.syncPowerOnBreath")
            if !synchronizePowerOnBreathEnabled {
                releasePendingSyncCohortToIndependentBreaths(reason: "sync disabled")
            }
        }
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

    private(set) var vehicleAutomationStatus = "Door day/night idle — following Center/BLEDOM power"
    private(set) var enginePowerPresent = false
    private(set) var enginePowerStatus = "Engine power unknown — waiting for HUD / OBD"
    private(set) var vehicleHeadlightsActive = false

    private var hudEnginePowerSignalPresent = false
    private var obdEnginePowerSignalPresent = false
    /// v90.16: HUD transport remains the primary engine-switched ON witness,
    /// matching the field-proven v90.10 behavior. OBD2 state is still evaluated:
    /// a positive OBD2/direct witness corroborates or preserves an existing ON
    /// session, while HUD + OBD2 absence must also survive the independent Door
    /// power witness before OFF can be confirmed. A missing HUD-side OBD event
    /// therefore cannot deadlock the entire ambient-light pipeline.
    private var engineSignalConsensusTask: Task<Void, Never>?
    private let engineSignalConsensusStabilitySeconds: TimeInterval = 0.75
    private var engineOffConfirmationTask: Task<Void, Never>?
    private var hudOutageBeganAt: Date?
    private var directOBDLastSeen = Date.distantPast
    private var directOBDPeripheralID: UUID?
    private var directOBDWitnessProven: Bool
    private let directOBDRecentSeconds: TimeInterval = 3.0
    // v90.15: allow enough time for the OBD adapter to resume direct advertising
    // during a HUD-only reboot before BOTH app-visible links are interpreted as an
    // engine-off candidate. Engine OFF is not latency-sensitive; false OFF is.
    private let directOBDAcquireWindowSeconds: TimeInterval = 5.0
    private(set) var independentOBDWitnessStatus = "Independent OBD witness not calibrated"

    // MARK: - v90 controller state

    private(set) var discoveredDevices: [AmbientDiscoveredDevice] = []
    private(set) var pairedDevices: [AmbientLightDevice]
    private(set) var groups: [AmbientLightGroup]
    private(set) var controllerStatus = "Ambient lighting disabled"

    private var central: CBCentralManager!
    private let bluetooth: HudBluetoothManager
    private let logger: LogManager

    /// Tracked Center/BLEDOM peripheral used for persistent CoreBluetooth
    /// presence/reconnection and the fast day/night signal. v90.18 deliberately
    /// restores the field-proven behavior: Center presence alone drives HUD Auto
    /// Brightness and Door day/night target; Dashboard remains a diagnostic cross-check.
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
    /// Target associated with the currently active fade. This prevents periodic
    /// or duplicate day/night events from cancelling and restarting the same
    /// transition before it can finish.
    private var brightnessTransitionTargetByID: [UUID: Int] = [:]
    /// One token is shared by every member of a group fade. Cancelling any member
    /// must clean up the whole shared task rather than leaving stale "fade" owners
    /// on the remaining members.
    private var brightnessTransitionTokenByID: [UUID: UUID] = [:]
    private var animatedConnectionSession: Set<UUID> = []
    private var sessionResetTasks: [UUID: Task<Void, Never>] = [:]

    /// v90.18 optional synchronization is based on the physical/GATT power-on
    /// cohort, not on whichever controller finishes preparation first. This is
    /// important because Center is immediately writable while BLEDIM intentionally
    /// waits for its 1.5 s boot settle.
    private var synchronizedBreathTask: Task<Void, Never>?
    private var pendingBreathStartTask: Task<Void, Never>?
    private var synchronizedBreathIDs: Set<UUID> = []       // prepared/ready members
    private var syncCohortExpectedIDs: Set<UUID> = []       // appeared during cohort window
    private var syncLateCohortIDs: Set<UUID> = []           // missed common T0; run independently
    private var syncCohortOpenedAt: Date?
    private let powerOnSyncWindowSeconds: TimeInterval = 3.0
    private let powerOnSyncPreparationGraceSeconds: TimeInterval = 1.5
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

    /// v90.15.1 narrow fail-safe. If an active Breath/fade is cancelled and no
    /// newer operation takes ownership of the light, restore its current steady
    /// target once. This intentionally does not reintroduce the v90.13 repeated
    /// recovery loop or alter the v90.10 animation transport.
    private var animationAbortFailsafeTasks: [UUID: Task<Void, Never>] = [:]

    /// v90.16 BLEDIM boot-settle safety. A newly powered BK-BLE controller may
    /// accept writeWithoutResponse packets before its firmware has finished
    /// settling, then revert to an internal/default state. Reassert the steady
    /// state once after GATT readiness, unless a newer animation/fade/warning
    /// has taken ownership. This is intentionally one-shot, not a periodic or
    /// multi-round recovery loop.
    private var bledimBootSettleTasks: [UUID: Task<Void, Never>] = [:]
    private let bledimBootSettleDelaySeconds: TimeInterval = 1.50

    /// v90.15.2 diagnostic flight recorder. These counters/signatures add
    /// event-driven state snapshots without changing BLE timing or animation
    /// behavior. The snapshots are intentionally emitted only on meaningful
    /// state-machine edges, never on the 20-Hz animation clock.
    private var ambientTraceSequence = 0
    /// Center/BLEDOM presence is the fast day/night signal, matching the older
    /// HUD-auto-brightness behavior that was field-proven before Door automation.
    /// Dashboard+Center consensus remains diagnostic only. This state affects Door
    /// steady brightness and HUD auto-brightness; it never gates a power-on Breath.
    private var headlightPowerSessionActive = false
    private var headlightStateGeneration = 0

    /// Dashboard + Center remain a two-sensor diagnostic cross-check. Their stable
    /// consensus is logged for the flight recorder but no longer delays the actual
    /// day/night edge, which follows Center immediately.
    private var headlightConsensusTask: Task<Void, Never>?
    private var headlightConsensusCandidate: HeadlightConsensusObservation?
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
        self.synchronizePowerOnBreathEnabled = d.object(forKey: "HUD.Ambient.v90_17.syncPowerOnBreath") == nil
            ? false : d.bool(forKey: "HUD.Ambient.v90_17.syncPowerOnBreath")
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
        migrateV9019BLEDIMPhysicalPowerSemanticsIfNeeded()
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

    /// v90.19 corrects the field-verified BK-BLE power-bit meaning. During the
    /// v90.18.2 field test the user intentionally set Door/Dashboard to OFF in
    /// the UI because that buggy mapping physically illuminated them. Those false
    /// values are therefore migration artifacts, not the intended steady config.
    /// Re-enable the two known vehicle BLEDIM roles exactly once after upgrading.
    private func migrateV9019BLEDIMPhysicalPowerSemanticsIfNeeded() {
        let key = "HUD.Ambient.v90_19.bledimPhysicalPowerSemanticsMigrated"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }

        var changed = false
        for index in pairedDevices.indices {
            guard pairedDevices[index].protocolKind == .bledim2,
                  pairedDevices[index].role == .door || pairedDevices[index].role == .dashboard
            else { continue }
            if !pairedDevices[index].powerOn {
                pairedDevices[index].powerOn = true
                changed = true
                logger.log(
                    "AMBIENT MIGRATE",
                    "v90.19 re-enabled \(pairedDevices[index].displayName) after correcting field-verified BLEDIM power semantics"
                )
            }
        }
        if changed { persistPairedDevices() }
        defaults.set(true, forKey: key)
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
        logger.log(
            "AMBIENT TRACE",
            "Flight recorder v90.19 enabled config{breathCycles=\(breathCycles),breathPerCycle=\(String(format: "%.1f", breathDurationSeconds))s,sync=\(synchronizePowerOnBreathEnabled ? 1 : 0),bledimBootSettle=\(String(format: "%.2f", bledimBootSettleDelaySeconds))s,syncWindow=\(String(format: "%.1f", powerOnSyncWindowSeconds))s,doorDay=\(doorDayBrightness)%,doorNight=\(doorNightBrightness)%,manualFade=\(String(format: "%.1f", brightnessTransitionSeconds))s,doorAutoFade=\(String(format: "%.1f", automaticDoorDayNightTransitionSeconds))s,crossCheckStable=\(String(format: "%.2f", headlightConsensusStabilitySeconds))s}"
        )
        ambientTrace("Ambient monitor start")
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
        brightnessTransitionTargetByID.removeAll()
        brightnessTransitionTokenByID.removeAll()
        synchronizedBreathTask?.cancel()
        synchronizedBreathTask = nil
        pendingBreathStartTask?.cancel()
        pendingBreathStartTask = nil
        activeBreathIDs.removeAll()
        synchronizedBreathIDs.removeAll()
        activeBreathStartBrightness.removeAll()
        activeBreathReturnBrightness.removeAll()
        activeBreathStartedAt = nil
        sessionResetTasks.values.forEach { $0.cancel() }
        sessionResetTasks.removeAll()
        restoreTasks.values.forEach { $0.cancel() }
        restoreTasks.removeAll()
        breathPrepareTasks.values.forEach { $0.cancel() }
        breathPrepareTasks.removeAll()
        animationAbortFailsafeTasks.values.forEach { $0.cancel() }
        animationAbortFailsafeTasks.removeAll()
        bledimBootSettleTasks.values.forEach { $0.cancel() }
        bledimBootSettleTasks.removeAll()
        headlightConsensusTask?.cancel()
        headlightConsensusTask = nil
        engineSignalConsensusTask?.cancel()
        engineSignalConsensusTask = nil
        overspeedWarningTask?.cancel()
        overspeedWarningTask = nil
        overspeedRestoreTask?.cancel()
        overspeedRestoreTask = nil
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
        removeFromActiveBreath(id)
        bledimBootSettleTasks[id]?.cancel()
        bledimBootSettleTasks[id] = nil
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

    /// Compact per-light state used by the diagnostic flight recorder.
    /// `conn` is CoreBluetooth connection, `gatt` is writable-control readiness,
    /// `logical` includes recent advertisements, and `ops` shows which operation
    /// currently owns the light.
    private func ambientRoleTraceState(_ role: AmbientLightRole) -> String {
        guard let id = deviceID(for: role), let device = pairedDevice(id) else {
            return "\(role.rawValue){unpaired}"
        }
        let connected = peripheralsByID[id]?.state == .connected
        let gatt = isControllable(id)
        let logical = isLogicallyPowered(id)
        var ops: [String] = []
        if activeBreathIDs.contains(id) { ops.append("breath") }
        if breathPrepareTasks[id] != nil { ops.append("prep") }
        if brightnessTransitionTasks[id] != nil { ops.append("fade") }
        if restoreTasks[id] != nil { ops.append("restore") }
        if animationAbortFailsafeTasks[id] != nil { ops.append("failsafe") }
        if bledimBootSettleTasks[id] != nil { ops.append("bootSettle") }
        if overspeedWarningActiveID == id { ops.append("warning") }
        let opText = ops.isEmpty ? "idle" : ops.joined(separator: "+")
        let recentAge: String
        if let seen = lastSeenByID[id] {
            recentAge = String(format: "%.1f", max(0, Date().timeIntervalSince(seen)))
        } else {
            recentAge = "na"
        }
        return "\(role.rawValue){conn=\(connected ? 1 : 0),gatt=\(gatt ? 1 : 0),logical=\(logical ? 1 : 0),seenAge=\(recentAge)s,cfgOn=\(device.powerOn ? 1 : 0),run=\(device.runtimeBrightness),pref=\(device.brightness),ops=\(opText)}"
    }

    /// v90.17 event-driven ambient state snapshot. Engine witnesses remain
    /// diagnostic only; power-on Breath admission is per-light. Dashboard +
    /// Center consensus owns only day/night state, Door target brightness, and
    /// HUD auto-brightness. This keeps post-drive logs aligned with the runtime.
    private func ambientTrace(_ reason: String) {
        ambientTraceSequence &+= 1
        if ambientTraceSequence <= 0 { ambientTraceSequence = 1 }
        let dayNightObservation = currentHeadlightConsensus().rawValue
        let directOBDRecent = isDirectOBDRecentlyPresent()
        let dayNight = headlightPowerSessionActive ? "night" : "day"
        logger.log(
            "AMBIENT TRACE",
            "#\(ambientTraceSequence) \(reason) | engineDiag{hud=\(hudEnginePowerSignalPresent ? 1 : 0),obd=\(obdEnginePowerSignalPresent ? 1 : 0),confirmed=\(enginePowerPresent ? 1 : 0),directOBD=\(directOBDRecent ? 1 : 0)} dayNight{raw=\(dayNightObservation),confirmed=\(dayNight),gen=\(headlightStateGeneration)} breath{sync=\(synchronizePowerOnBreathEnabled ? 1 : 0),active=\(activeBreathIDs.count),queued=\(synchronizedBreathIDs.count)} | \(ambientRoleTraceState(.door)) \(ambientRoleTraceState(.dashboard)) \(ambientRoleTraceState(.centerConsole))"
        )
    }

    private func cancelBrightnessTransition(for id: UUID) {
        guard let task = brightnessTransitionTasks[id] else {
            brightnessTransitionTargetByID[id] = nil
            brightnessTransitionTokenByID[id] = nil
            return
        }

        let token = brightnessTransitionTokenByID[id]
        let affectedIDs: [UUID]
        if let token {
            affectedIDs = brightnessTransitionTokenByID.compactMap { entryID, entryToken in
                entryToken == token ? entryID : nil
            }
        } else {
            affectedIDs = [id]
        }

        task.cancel()
        for affectedID in affectedIDs {
            brightnessTransitionTasks[affectedID] = nil
            brightnessTransitionTargetByID[affectedID] = nil
            brightnessTransitionTokenByID[affectedID] = nil
            logger.log(
                "AMBIENT FADE",
                "Brightness transition cancelled: \(pairedDevice(affectedID)?.displayName ?? affectedID.uuidString)"
            )
            ambientTrace("Brightness fade cancelled \(pairedDevice(affectedID)?.displayName ?? affectedID.uuidString)")
            scheduleAnimationAbortFailsafe(for: affectedID, reason: "brightness transition cancelled")
        }
    }

    private func scheduleAnimationAbortFailsafe(for id: UUID, reason: String) {
        animationAbortFailsafeTasks[id]?.cancel()
        if let device = pairedDevice(id) {
            logger.log(
                "AMBIENT FAILSAFE",
                "One-shot animation-abort fail-safe scheduled: \(device.displayName) reason=\(reason)"
            )
        }
        animationAbortFailsafeTasks[id] = Task { @MainActor [weak self] in
            // Let an intentional handoff (new fade, Breath, warning, manual power,
            // or explicit restore) claim the light first. Only an orphaned
            // transient animation state reaches the steady-state restore below.
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else { return }
            defer { self.animationAbortFailsafeTasks[id] = nil }

            guard self.enabled, let device = self.pairedDevice(id) else { return }
            var blockers: [String] = []
            if !device.powerOn { blockers.append("configuredPowerOff") }
            if !self.isControllable(id) { blockers.append("GATTNotReady") }
            if self.activeBreathIDs.contains(id) { blockers.append("newBreath") }
            if self.breathPrepareTasks[id] != nil { blockers.append("newBreathPrepare") }
            if self.brightnessTransitionTasks[id] != nil { blockers.append("newFade") }
            if self.restoreTasks[id] != nil { blockers.append("restoreAlreadyOwnsLight") }
            if self.overspeedWarningActiveID == id { blockers.append("overspeedOwnsLight") }

            if !blockers.isEmpty {
                self.logger.log(
                    "AMBIENT FAILSAFE",
                    "One-shot fail-safe yielded without restore: \(device.displayName) blockers=\(blockers.joined(separator: ",")) reason=\(reason)"
                )
                self.ambientTrace("Fail-safe yielded \(device.displayName) blockers=\(blockers.joined(separator: ","))")
                return
            }

            self.logger.log(
                "AMBIENT FAILSAFE",
                "Animation/fade aborted at transient level → restoring steady state: \(device.displayName) reason=\(reason)"
            )
            self.ambientTrace("Fail-safe restoring \(device.displayName)")
            self.restoreDeviceState(id)
        }
    }

    /// v90.17: a newly powered BLEDIM controller gets a quiet firmware-settle
    /// interval before the semantic Power ON → RGB → baseline → Breath sequence.
    /// This replaces the v90.16 mid-animation delayed reassert. The controller
    /// therefore receives one clean post-boot sequence rather than two owners
    /// competing over brightness.
    private func scheduleBLEDIMBootSettleReassert(for id: UUID, reason: String) {
        guard let device = pairedDevice(id), device.protocolKind == .bledim2 else { return }

        bledimBootSettleTasks[id]?.cancel()
        logger.log(
            "AMBIENT BLEDIM",
            "Fresh power-on boot settle scheduled: \(device.displayName) delay=\(String(format: "%.2f", bledimBootSettleDelaySeconds))s reason=\(reason)"
        )
        ambientTrace("BLEDIM fresh power-on boot settle \(device.displayName)")

        bledimBootSettleTasks[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.bledimBootSettleDelaySeconds))
            guard !Task.isCancelled else { return }
            self.bledimBootSettleTasks[id] = nil
            guard self.enabled, self.isControllable(id),
                  let current = self.pairedDevice(id), current.protocolKind == .bledim2 else { return }
            self.logger.log(
                "AMBIENT BLEDIM",
                "Fresh power-on boot settle complete: \(current.displayName); starting one complete power-on sequence"
            )
            self.ambientTrace("BLEDIM boot settled; power-on Breath admitted \(current.displayName)")
            self.queuePowerUpBreath(id)
        }
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
            brightnessTransitionTargetByID[id] = max(0, min(100, targets[id] ?? 0))
        }

        let starts = Dictionary(uniqueKeysWithValues: ids.compactMap { id in
            pairedDevice(id).map { (id, $0.runtimeBrightness) }
        })
        let duration = max(1.0, min(15.0, seconds))
        let timelineTick = 0.05
        let transitionToken = UUID()
        for id in ids { brightnessTransitionTokenByID[id] = transitionToken }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                for id in ids where self.brightnessTransitionTokenByID[id] == transitionToken {
                    self.brightnessTransitionTasks[id] = nil
                    self.brightnessTransitionTargetByID[id] = nil
                    self.brightnessTransitionTokenByID[id] = nil
                }
            }
            var lastSentLevel: [UUID: Int] = [:]
            var lastWriteAt: [UUID: Date] = [:]
            let startedAt = Date()
            self.logger.log(
                "AMBIENT FADE",
                "Smooth brightness transition begin ids=\(ids.count) duration=\(String(format: "%.1f", duration))s reason=\(reason) protocolPacing=20Hz/rawBLEDIM"
            )
            self.ambientTrace("Brightness fade begin ids=\(ids.count) reason=\(reason)")

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
            }
            self.logger.log("AMBIENT FADE", "Smooth brightness transition complete reason=\(reason)")
            self.ambientTrace("Brightness fade complete reason=\(reason)")
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

    /// v90.17 keeps Door day/night independent from engine/startup animation state.
    /// The current confirmed two-light headlight signal is the only automatic
    /// selector for the Door steady target.
    private func steadyBrightnessTarget(for device: AmbientLightDevice) -> Int {
        if vehicleAutomationEnabled, device.role == .door {
            return doorTargetBrightness(night: headlightPowerSessionActive)
        }
        return device.brightness
    }

    private func restoreDeviceState(_ id: UUID) {
        guard let device = pairedDevice(id), isControllable(id) else {
            if let device = pairedDevice(id) {
                logger.log(
                    "AMBIENT RESTORE",
                    "Steady restore deferred: \(device.displayName) GATT not controllable"
                )
            }
            return
        }
        restoreTasks[id]?.cancel()
        breathPrepareTasks[id]?.cancel()

        let runtimeTarget = steadyBrightnessTarget(for: device)

        logger.log(
            "AMBIENT RESTORE",
            "Steady restore begin: \(device.displayName) power=\(device.powerOn ? "ON" : "OFF") target=\(runtimeTarget)%"
        )
        ambientTrace("Steady restore begin \(device.displayName) target=\(runtimeTarget)%")

        restoreTasks[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.restoreTasks[id] = nil }

            if device.powerOn {
                // Ordering matters on write-without-response controllers. v90.9
                // could successfully send RGB and then silently drop Power ON and
                // brightness because the BLE buffer was temporarily full.
                guard await self.sendPowerWhenReady(id, on: true, reason: "restore") else {
                    self.logger.log("AMBIENT RESTORE", "Steady restore aborted at Power ON: \(device.displayName)")
                    self.ambientTrace("Steady restore failed power \(device.displayName)")
                    return
                }
                guard !Task.isCancelled else {
                    self.logger.log("AMBIENT RESTORE", "Steady restore cancelled after Power ON: \(device.displayName)")
                    return
                }
                let colorSent = await self.sendColorWhenReady(id, color: device.color, reason: "restore")
                guard !Task.isCancelled else {
                    self.logger.log("AMBIENT RESTORE", "Steady restore cancelled after RGB: \(device.displayName)")
                    return
                }
                let brightnessSent = await self.applyRuntimeBrightnessWhenReady(
                    id,
                    percent: runtimeTarget,
                    reason: "restore",
                    persist: true
                )
                self.logger.log(
                    "AMBIENT RESTORE",
                    "Steady restore complete: \(device.displayName) color=\(colorSent ? "sent" : "failed") brightness=\(brightnessSent ? "sent" : "failed") target=\(runtimeTarget)%"
                )
                self.ambientTrace("Steady restore complete \(device.displayName) target=\(runtimeTarget)% brightnessSent=\(brightnessSent ? 1 : 0)")
            } else {
                let sent = await self.sendPowerWhenReady(id, on: false, reason: "restore")
                self.logger.log(
                    "AMBIENT RESTORE",
                    "Steady restore power-OFF complete: \(device.displayName) sent=\(sent ? 1 : 0)"
                )
            }
        }
    }

    /// BLEDIM routine terminal commit stays brightness-only. The v90.18.2 field
    /// test showed that the extra command previously called Power ON was actually
    /// the inverted physical-OFF payload, explaining the visible terminal blink.
    /// With semantics corrected, there is still no reason to add a routine power
    /// command after a successful Breath; if the final brightness write fails,
    /// the existing one-shot fail-safe is still allowed to use the stronger semantic
    /// Power ON → RGB → brightness restore. Lotus keeps its established terminal
    /// commit because it does not exhibit the BLEDIM flash.
    private func finalizeBreathSteadyState(_ id: UUID, target: Int) async -> Bool {
        guard let device = pairedDevice(id), device.powerOn, isControllable(id) else { return false }
        if device.protocolKind == .bledim2 {
            let brightnessSent = await applyRuntimeBrightnessWhenReady(
                id, percent: target, reason: "power-up breath final (BLEDIM no-flash)", persist: true
            )
            logger.log(
                "AMBIENT ANIM",
                "Breath terminal no-flash commit \(device.displayName) brightness=\(brightnessSent ? 1 : 0) target=\(target)%"
            )
            ambientTrace("Breath terminal no-flash commit \(device.displayName) target=\(target)%")
            return brightnessSent
        }

        let powerSent = await sendPowerWhenReady(id, on: true, reason: "power-up breath terminal Power ON")
        guard powerSent, !Task.isCancelled else { return false }
        let colorSent = await sendColorWhenReady(id, color: device.color, reason: "power-up breath terminal RGB")
        guard !Task.isCancelled else { return false }
        let brightnessSent = await applyRuntimeBrightnessWhenReady(
            id, percent: target, reason: "power-up breath final", persist: true
        )
        logger.log(
            "AMBIENT ANIM",
            "Breath terminal steady commit \(device.displayName) power=\(powerSent ? 1 : 0) color=\(colorSent ? 1 : 0) brightness=\(brightnessSent ? 1 : 0) target=\(target)%"
        )
        ambientTrace("Breath terminal steady commit \(device.displayName) target=\(target)%")
        return powerSent && colorSent && brightnessSent
    }

    private func runStartupAnimationIfNeeded(_ id: UUID, force: Bool = false) {
        guard let device = pairedDevice(id) else { return }
        if force {
            queuePowerUpBreath(id, force: true)
            return
        }

        // Animation is strictly per physical/controller return. Engine, courtesy,
        // and day/night state never gate a light's own power-on Breath. When Sync
        // is enabled, register the power-on event BEFORE protocol-specific boot
        // preparation so BLEDIM's intentional settle delay cannot miss the cohort.
        if synchronizePowerOnBreathEnabled {
            registerPowerOnCohortMember(id)
        }
        if device.protocolKind == .bledim2 {
            scheduleBLEDIMBootSettleReassert(for: id, reason: "new GATT control ready")
        } else {
            queuePowerUpBreath(id)
        }
    }

    private func queuePowerUpBreath(_ id: UUID, force: Bool = false) {
        guard let device = pairedDevice(id) else { return }
        guard isControllable(id) else {
            logger.log("AMBIENT ANIM", "Breath request deferred: \(device.displayName) GATT not controllable")
            return
        }

        if activeBreathIDs.contains(id) || breathPrepareTasks[id] != nil {
            logger.log("AMBIENT ANIM", "Breath request ignored while already active/preparing: \(device.displayName); initial/return brightness preserved")
            return
        }

        if !force && animatedConnectionSession.contains(id) {
            logger.log("AMBIENT ANIM", "Breath withheld: \(device.displayName) already animated in current connection session; restoring steady state")
            restoreDeviceState(id)
            return
        }

        guard device.startupAnimationEnabled, device.powerOn else {
            logger.log(
                "AMBIENT ANIM",
                "Breath skipped by device setting: \(device.displayName) startupEnabled=\(device.startupAnimationEnabled ? 1 : 0) configuredPower=\(device.powerOn ? 1 : 0); restoring steady state"
            )
            animatedConnectionSession.insert(id)
            restoreDeviceState(id)
            return
        }

        cancelBrightnessTransition(for: id)
        restoreTasks[id]?.cancel()
        restoreTasks[id] = nil

        let initialBrightness = steadyBrightnessTarget(for: device)

        logger.log(
            "AMBIENT ANIM",
            "Breath prepare queued: \(device.displayName) role=\(device.role?.rawValue ?? "unassigned") initial=\(initialBrightness)% force=\(force ? 1 : 0)"
        )
        ambientTrace("Breath prepare queued \(device.displayName) initial=\(initialBrightness)%")

        breathPrepareTasks[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.breathPrepareTasks[id] = nil }

            // Critical preparation is serialized and retried instead of being
            // dropped under CoreBluetooth write-without-response backpressure.
            // BLEDIM-specific ordering preloads RGB + baseline BEFORE Power ON so
            // the controller does not visibly jump to its remembered/full level.
            // The immediate post-Power baseline reassert covers firmware that ignores
            // brightness while logically off. Lotus retains the proven old ordering.
            if device.protocolKind == .bledim2 {
                guard await self.sendColorWhenReady(id, color: device.color, reason: "power-up breath preload RGB") else {
                    self.logger.log("AMBIENT ANIM", "Breath prepare failed at BLEDIM preload RGB: \(device.displayName)")
                    self.scheduleAnimationAbortFailsafe(for: id, reason: "BLEDIM Breath preload RGB failed")
                    return
                }
                guard await self.applyRuntimeBrightnessWhenReady(
                    id, percent: initialBrightness, reason: "power-up breath preload baseline", persist: false
                ) else {
                    self.logger.log("AMBIENT ANIM", "Breath prepare failed at BLEDIM preload brightness: \(device.displayName)")
                    self.scheduleAnimationAbortFailsafe(for: id, reason: "BLEDIM Breath preload brightness failed")
                    return
                }
                guard await self.sendPowerWhenReady(id, on: true, reason: "power-up breath prepare no-flash Power ON") else {
                    self.logger.log("AMBIENT ANIM", "Breath prepare failed at Power ON: \(device.displayName)")
                    self.scheduleAnimationAbortFailsafe(for: id, reason: "Breath prepare Power ON failed")
                    return
                }
                guard !Task.isCancelled else { return }
                guard await self.applyRuntimeBrightnessWhenReady(
                    id, percent: initialBrightness, reason: "power-up breath post-Power baseline", persist: false
                ) else {
                    self.logger.log("AMBIENT ANIM", "Breath prepare failed at BLEDIM post-Power baseline: \(device.displayName)")
                    self.scheduleAnimationAbortFailsafe(for: id, reason: "BLEDIM Breath post-Power baseline failed")
                    return
                }
            } else {
                guard await self.sendPowerWhenReady(id, on: true, reason: "power-up breath prepare") else {
                    self.logger.log("AMBIENT ANIM", "Breath prepare failed at Power ON: \(device.displayName)")
                    self.ambientTrace("Breath prepare failed power \(device.displayName)")
                    self.scheduleAnimationAbortFailsafe(for: id, reason: "Breath prepare Power ON failed")
                    return
                }
                guard !Task.isCancelled else { return }
                guard await self.sendColorWhenReady(id, color: device.color, reason: "power-up breath prepare") else {
                    self.logger.log("AMBIENT ANIM", "Breath prepare failed at RGB: \(device.displayName)")
                    self.ambientTrace("Breath prepare failed RGB \(device.displayName)")
                    self.scheduleAnimationAbortFailsafe(for: id, reason: "Breath prepare RGB failed")
                    return
                }
                guard !Task.isCancelled else { return }
                guard await self.applyRuntimeBrightnessWhenReady(
                    id, percent: initialBrightness, reason: "power-up breath baseline", persist: false
                ) else {
                    self.logger.log("AMBIENT ANIM", "Breath prepare failed at baseline brightness: \(device.displayName) target=\(initialBrightness)%")
                    self.ambientTrace("Breath prepare failed baseline \(device.displayName)")
                    self.scheduleAnimationAbortFailsafe(for: id, reason: "Breath prepare baseline failed")
                    return
                }
            }
            guard !Task.isCancelled, self.isControllable(id) else {
                self.logger.log("AMBIENT ANIM", "Breath prepare lost ownership/GATT after baseline: \(device.displayName)")
                return
            }

            self.animatedConnectionSession.insert(id)

            // Day/night may change during the serialized Power/RGB/baseline
            // preparation. Re-read the automatic steady target now so the Breath
            // always returns to the newest Door mode even if that edge arrived in
            // the short preparation window. Manual Preview intentionally returns
            // to the current steady target captured at preview start. This deliberately
            // avoids recapturing a transient runtime brightness if Preview is used
            // as a recovery action immediately after an interrupted animation.
            let returnBrightness: Int
            if force {
                returnBrightness = initialBrightness
            } else if let latestDevice = self.pairedDevice(id) {
                returnBrightness = self.steadyBrightnessTarget(for: latestDevice)
            } else {
                returnBrightness = initialBrightness
            }

            self.activeBreathIDs.insert(id)
            self.activeBreathStartBrightness[id] = initialBrightness
            self.activeBreathReturnBrightness[id] = returnBrightness
            self.ambientTrace("Breath participant ready \(device.displayName) initial=\(initialBrightness)% return=\(returnBrightness)% sync=\(self.synchronizePowerOnBreathEnabled ? 1 : 0)")

            if !self.synchronizePowerOnBreathEnabled {
                self.startIndividualBreathSession(id)
                return
            }

            if self.syncLateCohortIDs.remove(id) != nil || self.synchronizedBreathTask != nil {
                self.logger.log("AMBIENT ANIM", "Power-on cohort already started; running complete independent Breath for \(device.displayName)")
                self.startIndividualBreathSession(id)
                return
            }

            if !self.syncCohortExpectedIDs.contains(id) {
                self.registerPowerOnCohortMember(id)
            }
            self.synchronizedBreathIDs.insert(id)
            self.logger.log(
                "AMBIENT ANIM",
                "Power-on cohort member prepared: \(device.displayName) ready=\(self.synchronizedBreathIDs.count)/\(self.syncCohortExpectedIDs.count)"
            )
        }
    }

    private func registerPowerOnCohortMember(_ id: UUID) {
        guard synchronizePowerOnBreathEnabled else { return }
        if synchronizedBreathTask != nil {
            syncLateCohortIDs.insert(id)
            logger.log("AMBIENT ANIM", "Power-on cohort already running; marked late member \(pairedDevice(id)?.displayName ?? id.uuidString)")
            return
        }

        let now = Date()
        if let opened = syncCohortOpenedAt {
            if now.timeIntervalSince(opened) <= powerOnSyncWindowSeconds {
                syncCohortExpectedIDs.insert(id)
                logger.log(
                    "AMBIENT ANIM",
                    "Power-on cohort joined: \(pairedDevice(id)?.displayName ?? id.uuidString) expected=\(syncCohortExpectedIDs.count)"
                )
            } else {
                syncLateCohortIDs.insert(id)
                logger.log("AMBIENT ANIM", "Power-on event arrived after cohort discovery window; marked late \(pairedDevice(id)?.displayName ?? id.uuidString)")
            }
            return
        }

        syncCohortOpenedAt = now
        syncCohortExpectedIDs = [id]
        synchronizedBreathIDs.removeAll()
        pendingBreathStartTask?.cancel()
        logger.log(
            "AMBIENT ANIM",
            "Power-on cohort opened discovery=\(String(format: "%.1f", powerOnSyncWindowSeconds))s preparationGrace=\(String(format: "%.1f", powerOnSyncPreparationGraceSeconds))s first=\(pairedDevice(id)?.displayName ?? id.uuidString)"
        )
        ambientTrace("Power-on sync cohort opened first=\(pairedDevice(id)?.displayName ?? id.uuidString)")

        pendingBreathStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.powerOnSyncWindowSeconds))
            guard !Task.isCancelled else { return }

            let graceDeadline = Date().addingTimeInterval(self.powerOnSyncPreparationGraceSeconds)
            while Date() < graceDeadline {
                guard !Task.isCancelled else { return }
                if self.syncCohortExpectedIDs.isSubset(of: self.synchronizedBreathIDs) { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }

            let expected = self.syncCohortExpectedIDs
            let ready = expected.intersection(self.synchronizedBreathIDs)
            let late = expected.subtracting(ready)
            self.syncLateCohortIDs.formUnion(late)
            self.synchronizedBreathIDs = ready
            self.syncCohortExpectedIDs.removeAll()
            self.syncCohortOpenedAt = nil
            self.pendingBreathStartTask = nil

            self.logger.log(
                "AMBIENT ANIM",
                "Power-on cohort common T0 ready=\(ready.count) late=\(late.count)"
            )
            self.ambientTrace("Power-on sync cohort T0 ready=\(ready.count) late=\(late.count)")
            self.startSynchronizedBreathSession()
        }
    }

    private func releasePendingSyncCohortToIndependentBreaths(reason: String) {
        pendingBreathStartTask?.cancel()
        pendingBreathStartTask = nil
        let ready = Array(synchronizedBreathIDs)
        syncLateCohortIDs.formUnion(syncCohortExpectedIDs.subtracting(synchronizedBreathIDs))
        syncCohortExpectedIDs.removeAll()
        synchronizedBreathIDs.removeAll()
        syncCohortOpenedAt = nil
        guard synchronizedBreathTask == nil else { return }
        for id in ready where activeBreathIDs.contains(id) {
            logger.log("AMBIENT ANIM", "Pending sync cohort released to independent Breath: \(pairedDevice(id)?.displayName ?? id.uuidString) reason=\(reason)")
            startIndividualBreathSession(id)
        }
    }

    private func startIndividualBreathSession(_ id: UUID) {
        guard animationTasks[id] == nil, activeBreathIDs.contains(id),
              let device = pairedDevice(id), isControllable(id),
              let start = activeBreathStartBrightness[id] else { return }

        let startedAt = Date()
        let cycles = max(2, min(5, breathCycles))
        let perCycleDuration = max(1.0, min(15.0, breathDurationSeconds))
        let totalDuration = perCycleDuration * Double(cycles)
        let timelineTick = 0.05
        logger.log(
            "AMBIENT ANIM",
            "Independent breath begin light=\(device.displayName) cycles=\(cycles) perCycle=\(String(format: "%.1f", perCycleDuration))s total=\(String(format: "%.1f", totalDuration))s pacing=20Hz/rawBLEDIM"
        )
        ambientTrace("Independent Breath begin \(device.displayName)")

        animationTasks[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastSentLevel: Int?
            var lastWriteAt = Date.distantPast

            while true {
                guard !Task.isCancelled, self.activeBreathIDs.contains(id), self.isControllable(id) else {
                    self.animationTasks[id] = nil
                    return
                }
                let now = Date()
                let elapsed = now.timeIntervalSince(startedAt)
                let progress = min(1.0, max(0.0, elapsed / totalDuration))
                let interval = self.animationWriteInterval(for: id)
                let due = progress >= 1.0 || now.timeIntervalSince(lastWriteAt) >= interval * 0.90
                if due {
                    let returnTarget = self.activeBreathReturnBrightness[id] ?? start
                    let normalized = self.breathBrightnessFraction(
                        start: start, returnTarget: returnTarget, progress: progress, cycles: cycles
                    )
                    let signature = self.animationLevelSignature(for: id, normalized: normalized)
                    if lastSentLevel != signature {
                        let maxSignature = device.protocolKind == .bledim2 ? 255 : 100
                        let logPacket = signature == 0 || signature == maxSignature
                        if self.applyRuntimeBrightnessNormalized(
                            id, normalized: normalized, reason: "independent power-up breath", logPacket: logPacket
                        ) {
                            lastSentLevel = signature
                            lastWriteAt = now
                        }
                    }
                }
                if progress >= 1.0 { break }
                try? await Task.sleep(for: .seconds(timelineTick))
            }

            guard !Task.isCancelled, self.isControllable(id) else {
                self.animationTasks[id] = nil
                return
            }
            let returnTarget = self.activeBreathReturnBrightness[id] ?? start
            let sent = await self.finalizeBreathSteadyState(id, target: returnTarget)
            self.animationTasks[id] = nil
            self.activeBreathIDs.remove(id)
            self.activeBreathStartBrightness[id] = nil
            self.activeBreathReturnBrightness[id] = nil
            if !sent {
                self.logger.log(
                    "AMBIENT FAILSAFE",
                    "Breath terminal commit failed: \(device.displayName); scheduling one-shot steady restore"
                )
                self.scheduleAnimationAbortFailsafe(for: id, reason: "Breath terminal steady commit failed")
            }
            self.logger.log(
                "AMBIENT ANIM",
                "Independent breath \(sent ? "complete" : "ended with failed terminal commit") light=\(device.displayName) final=\(returnTarget)% sent=\(sent ? 1 : 0) elapsed=\(String(format: "%.2f", Date().timeIntervalSince(startedAt)))s"
            )
            self.ambientTrace("Independent Breath ended \(device.displayName) final=\(returnTarget)% sent=\(sent ? 1 : 0)")
            if self.vehicleAutomationEnabled, device.role == .door {
                self.applyCurrentDoorDayNightTarget(reason: "post-breath door target")
            }
        }
    }

    private func startSynchronizedBreathSession() {
        guard synchronizedBreathTask == nil else { return }

        let ready = synchronizedBreathIDs.filter { id in
            guard let device = pairedDevice(id) else { return false }
            return device.startupAnimationEnabled && device.powerOn && isControllable(id)
        }
        guard !ready.isEmpty else {
            logger.log("AMBIENT ANIM", "Shared Breath start cancelled: no prepared participant remained controllable")
            ambientTrace("Shared Breath cancelled before start no-ready-participants")
            for id in synchronizedBreathIDs {
                activeBreathIDs.remove(id)
                activeBreathStartBrightness[id] = nil
                activeBreathReturnBrightness[id] = nil
            }
            synchronizedBreathIDs.removeAll()
            return
        }

        synchronizedBreathIDs = Set(ready)
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
        ambientTrace("Synchronized Breath begin lights=\(ready.count) cycles=\(cycles)")

        synchronizedBreathTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastSentLevel: [UUID: Int] = [:]
            var lastWriteAt: [UUID: Date] = [:]

            while true {
                guard !Task.isCancelled else { return }
                let now = Date()
                let elapsed = now.timeIntervalSince(startedAt)
                let progress = min(1.0, max(0.0, elapsed / totalDuration))
                let ids = Array(self.synchronizedBreathIDs)

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
            let finishedIDs = Array(self.synchronizedBreathIDs)
            var failedTerminalCommits: [UUID] = []
            for id in finishedIDs {
                guard let start = self.activeBreathStartBrightness[id] else { continue }
                let returnTarget = self.activeBreathReturnBrightness[id] ?? start
                if !(await self.finalizeBreathSteadyState(id, target: returnTarget)) {
                    failedTerminalCommits.append(id)
                }
            }

            self.synchronizedBreathTask = nil
            self.activeBreathStartedAt = nil
            for id in finishedIDs {
                self.activeBreathIDs.remove(id)
                self.activeBreathStartBrightness[id] = nil
                self.activeBreathReturnBrightness[id] = nil
            }
            self.synchronizedBreathIDs.removeAll()
            for id in failedTerminalCommits {
                self.logger.log(
                    "AMBIENT FAILSAFE",
                    "Synchronized Breath terminal commit failed: \(self.pairedDevice(id)?.displayName ?? id.uuidString); scheduling one-shot steady restore"
                )
                self.scheduleAnimationAbortFailsafe(for: id, reason: "Synchronized Breath terminal steady commit failed")
            }
            self.logger.log(
                "AMBIENT ANIM",
                "Synchronized breath ended lights=\(finishedIDs.count) terminalFailures=\(failedTerminalCommits.count) elapsed=\(String(format: "%.2f", Date().timeIntervalSince(startedAt)))s"
            )
            self.ambientTrace("Synchronized Breath ended lights=\(finishedIDs.count) terminalFailures=\(failedTerminalCommits.count)")

            if self.vehicleAutomationEnabled {
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
        let wasActive = activeBreathIDs.contains(id)
        animationTasks[id]?.cancel()
        animationTasks[id] = nil
        activeBreathIDs.remove(id)
        synchronizedBreathIDs.remove(id)
        syncCohortExpectedIDs.remove(id)
        syncLateCohortIDs.remove(id)
        activeBreathStartBrightness[id] = nil
        activeBreathReturnBrightness[id] = nil
        if wasActive {
            logger.log(
                "AMBIENT ANIM",
                "Breath participant removed/cancelled: \(pairedDevice(id)?.displayName ?? id.uuidString)"
            )
            ambientTrace("Breath participant cancelled \(pairedDevice(id)?.displayName ?? id.uuidString)")
            scheduleAnimationAbortFailsafe(for: id, reason: "Breath participation cancelled")
        }
        // A controller may disappear while a sync cohort is still waiting for its
        // other expected members to finish boot preparation. Do not collapse that
        // entire cohort merely because the prepared set is temporarily empty.
        if synchronizedBreathIDs.isEmpty && syncCohortExpectedIDs.isEmpty {
            pendingBreathStartTask?.cancel()
            pendingBreathStartTask = nil
            synchronizedBreathTask?.cancel()
            synchronizedBreathTask = nil
            activeBreathStartedAt = nil
            syncCohortOpenedAt = nil
        }
    }

    /// v90.17: every disconnect/reconnect is treated as a fresh power-on event.
    /// There is no 15-second replay suppression and no headlight animation epoch.
    private func scheduleStartupSessionReset(_ id: UUID) {
        sessionResetTasks[id]?.cancel()
        sessionResetTasks[id] = nil
        animatedConnectionSession.remove(id)
        logger.log("AMBIENT ANIM", "Power-on animation re-armed immediately after disconnect for \(pairedDevice(id)?.displayName ?? id.uuidString)")
    }

    // MARK: - Fast Center-driven day/night + diagnostic two-light cross-check

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

    /// v90.17 day/night consensus. Only BOTH ON or BOTH OFF can commit a
    /// stable day/night edge. A mixed state is transitional/unknown and preserves
    /// the previous mode. This signal never owns power-on animation.
    private func scheduleHeadlightConsensusEvaluation(reason: String) {
        let candidate = currentHeadlightConsensus()
        if candidate == .mixed {
            headlightConsensusTask?.cancel()
            headlightConsensusTask = nil
            if headlightConsensusCandidate != .mixed {
                headlightConsensusCandidate = .mixed
                logger.log(
                    "AMBIENT POWER",
                    "Headlight consensus candidate=mixed; preserving confirmed \(headlightPowerSessionActive ? "ON" : "OFF") state (\(reason))"
                )
                ambientTrace("Headlight candidate mixed reason=\(reason)")
            }
            return
        }

        // Critical v90.15.2 fix: repeated advertisements that report the SAME
        // candidate state must not restart the 0.75-s stability window. With
        // AllowDuplicates enabled, restarting on every packet could starve the
        // consensus forever even while both physical lights remained powered.
        if headlightConsensusCandidate == candidate {
            if headlightConsensusTask != nil { return }
            if candidate == .bothOn, headlightPowerSessionActive { return }
            if candidate == .bothOff, !headlightPowerSessionActive { return }
        }

        headlightConsensusTask?.cancel()
        headlightConsensusCandidate = candidate
        logger.log(
            "AMBIENT POWER",
            "Headlight consensus candidate=\(candidate.rawValue); stability timer \(String(format: "%.2f", headlightConsensusStabilitySeconds))s started (\(reason))"
        )
        ambientTrace("Headlight candidate \(candidate.rawValue) timer-start reason=\(reason)")

        headlightConsensusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.headlightConsensusStabilitySeconds))
            guard !Task.isCancelled else { return }
            self.headlightConsensusTask = nil

            let observation = self.currentHeadlightConsensus()
            guard observation == candidate else {
                self.logger.log(
                    "AMBIENT POWER",
                    "Headlight consensus candidate changed before commit expected=\(candidate.rawValue) actual=\(observation.rawValue); reevaluating"
                )
                self.headlightConsensusCandidate = nil
                self.scheduleHeadlightConsensusEvaluation(reason: "candidate changed during stability window")
                return
            }

            self.ambientTrace("Dashboard+Center diagnostic consensus stable observation=\(observation.rawValue) reason=\(reason)")
            self.logger.log(
                "AMBIENT POWER",
                "Dashboard+Center diagnostic consensus=\(observation.rawValue); Center/BLEDOM remains authoritative for fast day/night"
            )
        }
    }

    private func commitConfirmedHeadlightPower(_ on: Bool, reason: String) {
        guard headlightPowerSessionActive != on else { return }
        headlightPowerSessionActive = on
        headlightStateGeneration &+= 1
        vehicleHeadlightsActive = on

        logger.log(
            "AMBIENT POWER",
            "Fast Center day/night → \(on ? "NIGHT/ON" : "DAY/OFF") generation=\(headlightStateGeneration) (\(reason)); Dashboard consensus is diagnostic only"
        )
        ambientTrace("Center-driven day/night \(on ? "night" : "day") reason=\(reason)")

        if hudBrightnessTriggerEnabled, bluetooth.state == .connected {
            bluetooth.enqueue(
                HudCommands.autoBrightness(on),
                label: on
                    ? "Center presence → Auto brightness ON"
                    : "Center absence → Auto brightness OFF"
            )
            lastHUDReassertAt = Date()
        }

        if vehicleAutomationEnabled {
            applyCurrentDoorDayNightTarget(
                reason: on
                    ? "Center present → night Door brightness"
                    : "Center absent → day Door brightness"
            )
        }
    }

    /// Record headlight-fed controller evidence for the diagnostic Dashboard+Center
    /// cross-check. Center/BLEDOM presence itself owns the fast day/night state.
    private func noteHeadlightPowerSeen(_ id: UUID, reason: String) {
        guard isHeadlightFedDevice(id) else { return }
        scheduleHeadlightConsensusEvaluation(
            reason: "\(pairedDevice(id)?.displayName ?? id.uuidString) positive evidence via \(reason)"
        )
    }

    /// Compatibility call used by disconnect paths. This only refreshes the
    /// Dashboard+Center diagnostic cross-check; it cannot delay Center-driven day/night.
    private func scheduleHeadlightPowerOffEvaluation(reason: String) {
        scheduleHeadlightConsensusEvaluation(reason: reason)
    }

    private func headlightPowerPresent() -> Bool {
        // v90.18 fast path: this mirrors tracked Center/BLEDOM presence.
        headlightPowerSessionActive
    }

    private func doorTargetBrightness(night: Bool) -> Int {
        max(0, min(100, night ? doorNightBrightness : doorDayBrightness))
    }

    var doorBrightnessModeStatus: String {
        if !vehicleAutomationEnabled {
            return "Door day/night automation off • day \(doorDayBrightness)% • night \(doorNightBrightness)%"
        }
        let target = doorTargetBrightness(night: headlightPowerSessionActive)
        return "\(headlightPowerSessionActive ? "Night/Center ON" : "Day/Center OFF") • Door target \(target)%"
    }

    private func applyDoorTargetAfterSettingChange(changedNightTarget: Bool) {
        guard vehicleAutomationEnabled, enabled else { return }

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

    private enum EnginePowerConsensusObservation: String {
        case bothOn
        case bothOff
        case mixed
    }

    private func currentEnginePowerConsensus() -> EnginePowerConsensusObservation {
        if hudEnginePowerSignalPresent && obdEnginePowerSignalPresent { return .bothOn }
        if !hudEnginePowerSignalPresent && !obdEnginePowerSignalPresent { return .bothOff }
        return .mixed
    }

    /// v90.16: evaluate HUD + OBD2 together, but asymmetrically. Stable HUD
    /// transport is sufficient to create engine ON; OBD2 may corroborate it.
    /// For OFF, HUD + OBD2 must both be absent and the independent direct-OBD
    /// witness must also be absent. Door power is intentionally excluded because
    /// the vehicle retains Door accessory power after engine shutdown.
    private func scheduleEngineSignalConsensusEvaluation(reason: String) {
        engineSignalConsensusTask?.cancel()
        engineSignalConsensusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.engineSignalConsensusStabilitySeconds))
            guard !Task.isCancelled else { return }
            self.engineSignalConsensusTask = nil

            let observation = self.currentEnginePowerConsensus()
            self.ambientTrace("Engine witness evaluation observation=\(observation.rawValue) reason=\(reason)")

            // Field evidence from v90.15.2 showed that HUDWAY can remain fully
            // operational while its OBDConnectionEventPacket never reports
            // connected=true. Do not allow that optional through-HUD status to
            // block vehicle startup. A stable HUD transport is sufficient ON
            // evidence, as it was in v90.10.
            if self.hudEnginePowerSignalPresent {
                let source = self.obdEnginePowerSignalPresent
                    ? "stable HUD transport + OBD2 corroboration"
                    : "stable HUD transport (OBD2 not yet confirmed)"
                if !self.obdEnginePowerSignalPresent {
                    self.logger.log(
                        "AMBIENT ENGINE",
                        "HUD confirms engine ON; OBD2 app-visible state is not connected, using it as secondary corroboration rather than an ON gate (\(reason))"
                    )
                }
                self.confirmEnginePowerOn(source: source)
                return
            }

            // OBD-through-HUD can briefly outlive a HUD state callback ordering
            // edge. It may preserve a confirmed ON session, but does not create a
            // brand-new engine session without the primary HUD witness.
            if self.obdEnginePowerSignalPresent {
                self.engineOffConfirmationTask?.cancel()
                self.engineOffConfirmationTask = nil
                self.enginePowerStatus = self.enginePowerPresent
                    ? "Engine ON preserved • OBD2 witness present while HUD unavailable"
                    : "Engine not confirmed • OBD2 present, waiting for HUD transport"
                self.logger.log(
                    "AMBIENT ENGINE",
                    "OBD2-only engine evidence; preserving confirmed \(self.enginePowerPresent ? "ON" : "OFF") state (\(reason))"
                )
                return
            }

            // Both app-visible transport witnesses are absent. Before OFF is
            // allowed, give the direct OBD scan and the independently powered
            // Door controller a chance to prove that only the HUD rebooted.
            guard self.enginePowerPresent else {
                self.enginePowerStatus = "Engine power OFF • HUD + OBD2 absent"
                return
            }

            if self.isDirectOBDRecentlyPresent() {
                self.engineOffConfirmationTask?.cancel()
                self.engineOffConfirmationTask = nil
                self.enginePowerStatus = "Engine ON preserved • direct OBD witness present"
                self.logger.log(
                    "AMBIENT ENGINE",
                    "HUD + OBD2 absent, but independent OBD witness vetoes engine OFF (\(reason))"
                )
                return
            }

            if let began = self.hudOutageBeganAt,
               Date().timeIntervalSince(began) < self.directOBDAcquireWindowSeconds {
                self.enginePowerStatus = "HUD + OBD2 absent • checking direct OBD witness…"
                self.logger.log(
                    "AMBIENT ENGINE",
                    "HUD + OBD2 both absent; holding OFF decision during witness acquisition window (\(reason))"
                )
                return
            }

            self.scheduleEnginePowerOffConfirmation(
                source: "HUD + OBD2 absent and direct-OBD witness absent; \(reason)"
            )
        }
    }

    /// HUD is the primary field-proven engine-ON witness. OBD2 remains a second
    /// safety signal: it can corroborate ON and veto OFF, but a missing through-HUD
    /// OBD connection event cannot prevent a valid vehicle session from starting.
    func hudTransportPowerSignal(_ present: Bool) {
        let changed = hudEnginePowerSignalPresent != present
        hudEnginePowerSignalPresent = present
        if present {
            hudOutageBeganAt = nil
        } else {
            hudOutageBeganAt = Date()
        }
        if changed {
            logger.log("AMBIENT ENGINE", "Raw HUD engine witness → \(present ? "ON" : "OFF")")
            ambientTrace("HUD engine witness changed")
            scheduleEngineSignalConsensusEvaluation(reason: present ? "HUD connected" : "HUD disconnected")
        }
    }

    func obdPowerSignal(_ present: Bool) {
        let changed = obdEnginePowerSignalPresent != present
        obdEnginePowerSignalPresent = present
        if changed {
            logger.log("AMBIENT ENGINE", "Raw OBD2 engine witness → \(present ? "ON" : "OFF")")
            ambientTrace("OBD2 engine witness changed")
            scheduleEngineSignalConsensusEvaluation(reason: present ? "OBD2 connected" : "OBD2 disconnected")
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
        if enginePowerPresent,
           !hudEnginePowerSignalPresent,
           !obdEnginePowerSignalPresent {
            engineOffConfirmationTask?.cancel()
            engineOffConfirmationTask = nil
            enginePowerStatus = "Engine ON preserved • direct OBD witness present during HUD/OBD outage"
        }
    }

    private func isDirectOBDRecentlyPresent(now: Date = Date()) -> Bool {
        directOBDWitnessProven && now.timeIntervalSince(directOBDLastSeen) <= directOBDRecentSeconds
    }

    private func evaluateIndependentOBDWitnessForEngineState(now: Date = Date()) {
        if hudEnginePowerSignalPresent {
            if enginePowerPresent {
                engineOffConfirmationTask?.cancel()
                engineOffConfirmationTask = nil
                enginePowerStatus = obdEnginePowerSignalPresent
                    ? "Engine power ON • HUD transport + OBD2 corroboration"
                    : "Engine power ON • HUD transport"
            } else if engineSignalConsensusTask == nil {
                scheduleEngineSignalConsensusEvaluation(reason: "watchdog stable-HUD evaluation")
            }
            return
        }

        if obdEnginePowerSignalPresent {
            if enginePowerPresent {
                engineOffConfirmationTask?.cancel()
                engineOffConfirmationTask = nil
                enginePowerStatus = "Engine ON preserved • OBD2 connected while HUD unavailable"
            }
            return
        }

        if isDirectOBDRecentlyPresent(now: now) {
            if enginePowerPresent {
                engineOffConfirmationTask?.cancel()
                engineOffConfirmationTask = nil
                enginePowerStatus = "Engine ON preserved • direct OBD witness present"
            }
            return
        }

        guard enginePowerPresent else { return }

        if let began = hudOutageBeganAt,
           now.timeIntervalSince(began) < directOBDAcquireWindowSeconds {
            enginePowerStatus = "HUD + OBD2 absent • checking direct OBD witness…"
            return
        }

        scheduleEnginePowerOffConfirmation(
            source: "HUD absent and OBD/direct-OBD witnesses absent"
        )
    }

    private func confirmEnginePowerOn(source: String) {
        engineOffConfirmationTask?.cancel()
        engineOffConfirmationTask = nil
        let wasOff = !enginePowerPresent
        enginePowerPresent = true
        enginePowerStatus = "Engine power ON • \(source)"
        if wasOff {
            logger.log(
                "AMBIENT ENGINE",
                "Engine diagnostic ON via \(source); v90.17 does not gate or re-arm ambient animations from engine state"
            )
            ambientTrace("Engine diagnostic ON source=\(source)")
        }
    }

    private func scheduleEnginePowerOffConfirmation(source: String) {
        guard enginePowerPresent else {
            enginePowerStatus = "Engine power OFF / unavailable"
            return
        }
        guard !hudEnginePowerSignalPresent, !obdEnginePowerSignalPresent else {
            enginePowerStatus = "Engine ON preserved • HUD/OBD2 not both absent"
            return
        }
        guard !isDirectOBDRecentlyPresent() else {
            enginePowerStatus = "Engine ON preserved • direct OBD witness present"
            return
        }
        guard engineOffConfirmationTask == nil else { return }

        let delay = max(0.5, engineOffConfirmationSeconds)
        enginePowerStatus = "Engine power OFF candidate • HUD/OBD witnesses absent • confirming \(String(format: "%.1f", delay))s"
        logger.log("AMBIENT ENGINE", "\(source); HUD/OBD witnesses absent; confirming engine OFF for \(String(format: "%.1f", delay))s")
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
        enginePowerStatus = "Engine power OFF • diagnostic witnesses absent"
        independentOBDWitnessStatus = directOBDWitnessProven
            ? "Calibrated OBD witness absent"
            : "Independent OBD witness not calibrated"
        logger.log(
            "AMBIENT ENGINE",
            "Engine diagnostic OFF confirmed; v90.18 leaves all light animations and Center-driven day/night behavior untouched"
        )
        ambientTrace("Engine diagnostic OFF")
    }

    /// v90.18: vehicle automation only means Door day/night brightness. It is
    /// intentionally independent from engine/courtesy/startup state. Fast tracked
    /// Center/BLEDOM presence is the automatic day/night input; Dashboard+Center
    /// consensus remains diagnostic only.
    private func evaluateVehicleLightingAutomation() {
        guard vehicleAutomationEnabled, enabled else { return }
        vehicleHeadlightsActive = headlightPowerSessionActive
        vehicleAutomationStatus = headlightPowerSessionActive
            ? "Night/Center ON • Door target \(doorNightBrightness)%"
            : "Day/Center OFF • Door target \(doorDayBrightness)%"
        applyCurrentDoorDayNightTarget(reason: "Center-driven day/night evaluation")
    }

    private func applyCurrentDoorDayNightTarget(reason: String) {
        guard vehicleAutomationEnabled,
              let doorID = deviceID(for: .door),
              isLogicallyPowered(doorID), isControllable(doorID),
              let door = pairedDevice(doorID) else { return }

        let target = doorTargetBrightness(night: headlightPowerSessionActive)
        if bledimBootSettleTasks[doorID] != nil || breathPrepareTasks[doorID] != nil {
            logger.log("AMBIENT AUTO", "Door target updated to \(target)% while power-on sequence is preparing; animation will use the latest target (\(reason))")
            return
        }
        if activeBreathIDs.contains(doorID) {
            if activeBreathReturnBrightness[doorID] != target {
                activeBreathReturnBrightness[doorID] = target
                logger.log("AMBIENT ANIM", "Door breath final target updated to \(target)% reason=\(reason)")
            }
            return
        }
        if brightnessTransitionTasks[doorID] != nil, brightnessTransitionTargetByID[doorID] == target {
            return
        }
        if door.runtimeBrightness == target { return }
        transitionBrightness(
            ids: [doorID],
            targets: [doorID: target],
            over: automaticDoorDayNightTransitionSeconds,
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
        let devices = pairedDevices.filter { $0.startupAnimationEnabled && $0.powerOn && isControllable($0.id) }
        if synchronizePowerOnBreathEnabled {
            // Register the whole Preview set before any participant starts preparing;
            // this gives Preview the same true common-T0 behavior as automatic power-on.
            for device in devices { registerPowerOnCohortMember(device.id) }
        }
        for device in devices {
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
        return steadyBrightnessTarget(for: device)
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

    // MARK: - Tracked Center presence / persistent connection

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
                "\(name) became present via \(reason); fast Center day/night → NIGHT"
            )
            commitConfirmedHeadlightPower(true, reason: "Center/BLEDOM present via \(reason)")
        }
    }

    private func markAbsent(reason: String) {
        guard lightPresent else { return }
        lightPresent = false
        status = "\(targetName) absent"
        logger.log(
            "AMBIENT",
            "\(targetName) became absent via \(reason); fast Center day/night → DAY"
        )
        commitConfirmedHeadlightPower(false, reason: "Center/BLEDOM absent via \(reason)")
        if let trackedID = trackedPeripheral?.identifier, isHeadlightFedDevice(trackedID) {
            scheduleHeadlightPowerOffEvaluation(reason: "tracked Center became absent via \(reason)")
        }
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
            label: "HUD rehydrate → Center-driven auto brightness \(shouldEnable ? "ON" : "OFF")"
        )
        lastHUDReassertAt = Date()

        logger.log(
            "AMBIENT SESSION",
            "Rehydrated Center-driven brightness=\(shouldEnable) centerConnected=\(connectedPresence) centerRecentAdvertisement=\(recentAdvertisement)"
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
            // v90.17: every controller return is a brand-new power-on event.
            self.animatedConnectionSession.remove(id)
            self.noteHeadlightPowerSeen(id, reason: "didConnect")
            if let device = self.pairedDevice(id) {
                self.ambientTrace("BLE connected role=\(device.role?.rawValue ?? "unassigned") name=\(device.displayName)")
            }

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
            self.bledimBootSettleTasks[id]?.cancel()
            self.bledimBootSettleTasks[id] = nil
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
            if let device = self.pairedDevice(id) {
                self.ambientTrace("BLE disconnected role=\(device.role?.rawValue ?? "unassigned") name=\(device.displayName) error=\(error?.localizedDescription ?? "none")")
            }

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
                self.ambientTrace("GATT control ready role=\(device.role?.rawValue ?? "unassigned") name=\(device.displayName)")
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

                if self.hudBrightnessTriggerEnabled,
                   self.bluetooth.state == .connected,
                   Date().timeIntervalSince(self.lastHUDReassertAt) >= 10 {
                    let shouldEnable = self.headlightPowerSessionActive
                    self.bluetooth.enqueue(
                        HudCommands.autoBrightness(shouldEnable),
                        label: "Ambient watchdog reassert → Center-driven Auto brightness \(shouldEnable ? "ON" : "OFF")"
                    )
                    self.lastHUDReassertAt = Date()
                    self.logger.log(
                        "AMBIENT HUD",
                        "Center-driven watchdog reasserted HUD auto brightness=\(shouldEnable ? "ON" : "OFF")"
                    )
                }

                self.evaluateIndependentOBDWitnessForEngineState()
            }
        }
    }
}

import Foundation

/// App-level protocol adapters for the inexpensive BLE ambient-light controllers.
/// The UI and grouping layer never need to know packet details.

/// v90.21 in-car diagnostic strategies for BLEDIM Door/Dashboard Breath sequencing.
/// The known-good v90.17.2 strategy remains the automatic default. Experimental
/// strategies can be exercised from Preview without rebuilding the app.
enum BLEDIMAnimationStrategy: String, CaseIterable, Identifiable {
    case v90172Baseline
    case baselineHold
    case brightnessOnlyFinish
    case noTerminalCommit
    case alreadyOnMinimal
    case v9018NoFlash

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .v90172Baseline: return "17.2 Baseline"
        case .baselineHold: return "17.2 + Hold"
        case .brightnessOnlyFinish: return "No End Power"
        case .noTerminalCommit: return "No End Commit"
        case .alreadyOnMinimal: return "Already-On Minimal"
        case .v9018NoFlash: return "18 No-Flash"
        }
    }

    var sequenceDescription: String {
        switch self {
        case .v90172Baseline:
            return "Power ON → RGB → Preferred | Breath | Power ON → RGB → Preferred"
        case .baselineHold:
            return "Power ON → RGB → Preferred → hold 0.75 s | Breath | Power ON → RGB → Preferred"
        case .brightnessOnlyFinish:
            return "Power ON → RGB → Preferred | Breath | Preferred only"
        case .noTerminalCommit:
            return "Power ON → RGB → Preferred | Breath | no extra terminal command"
        case .alreadyOnMinimal:
            return "No preparation write | Breath | Preferred only (for lights already ON)"
        case .v9018NoFlash:
            return "RGB → Preferred → Power ON → Preferred | Breath | Preferred only"
        }
    }

    var diagnosticPurpose: String {
        switch self {
        case .v90172Baseline:
            return "Known field-good control. Use this first to confirm the controller is behaving normally."
        case .baselineHold:
            return "Same known-good commands with a pause before Breath. If a flash occurs during the pause, preparation is the cause; if it begins after the pause, the waveform is the cause."
        case .brightnessOnlyFinish:
            return "Keeps proven startup preparation but removes terminal Power ON/RGB. Best candidate for isolating the end flash."
        case .noTerminalCommit:
            return "Tests whether any extra terminal command is responsible; relies on the final Breath frame already landing at Preferred."
        case .alreadyOnMinimal:
            return "Tests whether preparation itself creates the start flash. Intended for Preview while Door/Dashboard are already steadily ON."
        case .v9018NoFlash:
            return "Exact v90.18 BLEDIM no-flash experiment for comparison. This sequence was not field reliable as the automatic startup path."
        }
    }
}

enum AmbientLightProtocolKind: String, Codable, CaseIterable, Identifiable {
    case lotusLantern
    case bledim2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lotusLantern: return "Lotus Lantern / ELK-BLEDOM"
        case .bledim2: return "BLEDIM2 / FFF1"
        }
    }

    var controlStatus: String {
        switch self {
        case .lotusLantern: return "Control protocol verified from Lotus Lantern 6.5.08"
        case .bledim2: return "Control protocol recovered from official BLEDIM2 iOS Bluetooth capture"
        }
    }
}

/// Physical role is deliberately independent of BLE protocol. The vehicle-state
/// choreography is based on how each controller is powered in the car.
enum AmbientOverspeedWarningLight: String, CaseIterable, Identifiable {
    case door = "Door"
    case dashboard = "Dashboard"

    var id: String { rawValue }

    var role: AmbientLightRole {
        switch self {
        case .door: return .door
        case .dashboard: return .dashboard
        }
    }
}

enum AmbientLightRole: String, Codable, CaseIterable, Identifiable {
    case door
    case dashboard
    case centerConsole

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .door: return "Door light"
        case .dashboard: return "Dashboard light"
        case .centerConsole: return "Center console light"
        }
    }

    var powerSourceDescription: String {
        switch self {
        case .door: return "Vehicle / retained accessory power"
        case .dashboard, .centerConsole: return "Headlight circuit"
        }
    }

    var isHeadlightFed: Bool {
        self == .dashboard || self == .centerConsole
    }
}

struct AmbientRGB: Codable, Equatable {
    var red: Int
    var green: Int
    var blue: Int

    static let white = AmbientRGB(red: 255, green: 255, blue: 255)
    static let defaultPresets: [AmbientRGB] = [
        AmbientRGB(red: 255, green: 0, blue: 0),
        AmbientRGB(red: 0, green: 255, blue: 0),
        AmbientRGB(red: 0, green: 80, blue: 255),
        AmbientRGB(red: 160, green: 64, blue: 255),
        AmbientRGB(red: 255, green: 255, blue: 255)
    ]

    init(red: Int, green: Int, blue: Int) {
        self.red = max(0, min(255, red))
        self.green = max(0, min(255, green))
        self.blue = max(0, min(255, blue))
    }
}

struct AmbientLightDevice: Identifiable, Codable, Equatable {
    var id: UUID
    var customName: String
    var advertisedName: String
    var protocolKind: AmbientLightProtocolKind
    var autoConnect: Bool
    var color: AmbientRGB

    /// User's preferred steady-state brightness. Vehicle shutdown animation must
    /// NEVER overwrite this value.
    var brightness: Int

    /// Last brightness the app actually attempted to apply. Optional keeps v89
    /// persisted records backward compatible. After a shutdown fade this becomes
    /// 0 while `brightness` remains the preferred target for the next startup.
    var lastAppliedBrightness: Int?

    var powerOn: Bool
    var startupAnimationEnabled: Bool
    var startupCycles: Int
    var startupDurationSeconds: Double

    /// v90.8: five user-editable color shortcuts. Optional preserves decoding of
    /// every previously persisted v89-v90.7 device record.
    var presetColors: [AmbientRGB]?

    /// Wiring role used by v90 vehicle-aware automation. Optional so existing v89
    /// records decode cleanly; known car UUIDs are migrated automatically.
    var role: AmbientLightRole?

    init(
        id: UUID,
        customName: String,
        advertisedName: String,
        protocolKind: AmbientLightProtocolKind,
        autoConnect: Bool = true,
        color: AmbientRGB = .white,
        brightness: Int = 100,
        lastAppliedBrightness: Int? = nil,
        powerOn: Bool = true,
        startupAnimationEnabled: Bool = false,
        startupCycles: Int = 1,
        startupDurationSeconds: Double = 1.5,
        presetColors: [AmbientRGB]? = nil,
        role: AmbientLightRole? = nil
    ) {
        self.id = id
        self.customName = customName
        self.advertisedName = advertisedName
        self.protocolKind = protocolKind
        self.autoConnect = autoConnect
        self.color = color
        self.brightness = max(0, min(100, brightness))
        self.lastAppliedBrightness = lastAppliedBrightness.map { max(0, min(100, $0)) }
        self.powerOn = powerOn
        self.startupAnimationEnabled = startupAnimationEnabled
        self.startupCycles = max(1, min(5, startupCycles))
        self.startupDurationSeconds = max(1.0, min(15.0, startupDurationSeconds))
        self.presetColors = presetColors
        self.role = role
    }

    var displayName: String {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let advertised = advertisedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !advertised.isEmpty { return advertised }
        return "Ambient Light \(id.uuidString.suffix(4))"
    }

    var runtimeBrightness: Int {
        max(0, min(100, lastAppliedBrightness ?? brightness))
    }

    var resolvedPresetColors: [AmbientRGB] {
        Self.normalizedPresets(presetColors)
    }

    static func normalizedPresets(_ presets: [AmbientRGB]?) -> [AmbientRGB] {
        var values = Array((presets ?? AmbientRGB.defaultPresets).prefix(5))
        while values.count < 5 {
            values.append(AmbientRGB.defaultPresets[values.count])
        }
        return values
    }
}

struct AmbientLightGroup: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var memberIDs: [UUID]

    /// v90.8: group-specific five-color shortcuts. Optional keeps older saved
    /// group JSON fully backward compatible.
    var presetColors: [AmbientRGB]?

    init(id: UUID = UUID(), name: String, memberIDs: [UUID] = [], presetColors: [AmbientRGB]? = nil) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
        self.presetColors = presetColors
    }

    var resolvedPresetColors: [AmbientRGB] {
        var values = Array((presetColors ?? AmbientRGB.defaultPresets).prefix(5))
        while values.count < 5 {
            values.append(AmbientRGB.defaultPresets[values.count])
        }
        return values
    }
}

struct AmbientDiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    var advertisedName: String
    var rssi: Int
    var serviceUUIDs: [String]
    var lastSeen: Date

    var displayName: String {
        let trimmed = advertisedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unnamed BLE \(id.uuidString.suffix(4))" : trimmed
    }
}

/// Exact packets recovered from Lotus Lantern 6.5.08's BluetoothLEService.
enum LotusLanternProtocol {
    static let serviceUUID = CBUUIDString.fff0
    static let writeCharacteristicUUID = CBUUIDString.fff3

    static func power(_ on: Bool) -> Data {
        if on {
            return Data([0x7E, 0x04, 0x04, 0x01, 0x00, 0x01, 0xFF, 0x00, 0xEF])
        }
        return Data([0x7E, 0x04, 0x04, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xEF])
    }

    static func color(_ rgb: AmbientRGB) -> Data {
        Data([
            0x7E, 0x07, 0x05, 0x03,
            UInt8(rgb.red), UInt8(rgb.green), UInt8(rgb.blue),
            0x10, 0xEF
        ])
    }

    static func brightness(_ percent: Int, lightMode: UInt8 = 0xFF) -> Data {
        let value = UInt8(max(0, min(100, percent)))
        return Data([0x7E, 0x04, 0x01, value, lightMode, 0xFF, 0xFF, 0x00, 0xEF])
    }
}

/// v90.7 BLEDIM2 protocol recovered directly from the official BLEDIM2 iOS app.
/// The 2026-08-24 Apple PacketLogger/sysdiagnose capture shows ATT Write Commands
/// to FFF0 -> FFF1 with a 55 AA framed protocol:
///   55 AA <sequence> <command> <length-be16> <payload...> <checksum>
/// where checksum is the modulo-256 sum of every preceding byte in the frame.
/// Captured commands: 0x80 power, 0x82 RGB, 0x88 brightness.
enum BLEDIM2Protocol {
    static let serviceUUID = CBUUIDString.fff0
    static let writeCharacteristicUUID = CBUUIDString.fff1

    /// v90.20 rollback: exact field-proven v90.17.2 BLEDIM power mapping.
    /// ON uses payload 0x01; OFF uses payload 0x00. The v90.18-v90.19
    /// experiments that reinterpreted/reordered this command regressed both
    /// manual power and Preview on the actual Door/Dashboard controllers.
    static func power(_ on: Bool, sequence: UInt8) -> Data {
        frame(sequence: sequence, command: 0x80, payload: [on ? 0x01 : 0x00])
    }

    static func color(_ rgb: AmbientRGB, sequence: UInt8) -> Data {
        // Exact 12-byte payload shape observed from official BLEDIM2:
        // 00 RR GG BB 00 00 FF 00 80 00 00 00
        frame(
            sequence: sequence,
            command: 0x82,
            payload: [
                0x00, UInt8(rgb.red), UInt8(rgb.green), UInt8(rgb.blue),
                0x00, 0x00, 0xFF, 0x00, 0x80, 0x00, 0x00, 0x00
            ]
        )
    }

    static func brightness(_ percent: Int, sequence: UInt8) -> Data {
        let clamped = max(0, min(100, percent))
        let value = UInt8((Double(clamped) * 255.0 / 100.0).rounded())
        return brightnessRaw(value, sequence: sequence)
    }

    /// The official controller exposes 256 brightness steps even though our UI is
    /// intentionally 0...100%. Animation code uses the raw byte so slow fades do
    /// not collapse to only 101 rounded steps near the dark end.
    static func brightnessRaw(_ value: UInt8, sequence: UInt8) -> Data {
        frame(
            sequence: sequence,
            command: 0x88,
            payload: [0x02, value, 0x00, 0x00, 0x00, 0x00]
        )
    }

    static func frame(sequence: UInt8, command: UInt8, payload: [UInt8]) -> Data {
        precondition(payload.count <= Int(UInt16.max))
        let length = UInt16(payload.count)
        var bytes: [UInt8] = [
            0x55, 0xAA, sequence, command,
            UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)
        ]
        bytes.append(contentsOf: payload)
        let checksum = UInt8(truncatingIfNeeded: bytes.reduce(0) { $0 + Int($1) })
        bytes.append(checksum)
        return Data(bytes)
    }
}

/// Keep UUID literals in one place while still making the recovered values
/// obvious in source/tests.
private enum CBUUIDString {
    static let fff0 = "0000FFF0-0000-1000-8000-00805F9B34FB"
    static let fff1 = "0000FFF1-0000-1000-8000-00805F9B34FB"
    static let fff3 = "0000FFF3-0000-1000-8000-00805F9B34FB"
}

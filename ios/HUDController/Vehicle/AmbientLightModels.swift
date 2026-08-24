import Foundation

/// App-level protocol adapters for the inexpensive BLE ambient-light controllers.
/// The UI and grouping layer never need to know packet details.
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
        self.startupCycles = max(1, min(2, startupCycles))
        self.startupDurationSeconds = max(0.4, min(5.0, startupDurationSeconds))
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
}

struct AmbientLightGroup: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var memberIDs: [UUID]

    init(id: UUID = UUID(), name: String, memberIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
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
        // Official app transmits the brightness channel on a 0...255 scale.
        let value = UInt8((Double(clamped) * 255.0 / 100.0).rounded())
        return frame(
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

import Foundation

enum HudCommands {
    static func uartConnectionCheck() -> Data { HudProtocol.frame(command: 2, p1: 6, p2: 0) }
    static func keepAlive() -> Data { HudProtocol.frame(command: 2, p1: 15, p2: 0) }

    static func navigationState(_ enabled: Bool) -> Data {
        HudProtocol.frame(command: 2, p1: 101, p2: 0, payload: HudProtocol.int32(enabled ? 1 : 0))
    }

    static func autoBrightness(_ enabled: Bool) -> Data {
        HudProtocol.frame(command: 2, p1: 2, p2: 1, payload: Data([enabled ? 1 : 0]))
    }

    static func manualBrightness(_ value: Int) -> Data {
        let clamped = max(0, min(100, value))
        var payload = HudProtocol.int32(Int32(clamped))
        payload.append(0)
        return HudProtocol.frame(command: 2, p1: 2, p2: 4, payload: payload)
    }

    static func fullScreen(_ enabled: Bool) -> Data {
        HudProtocol.frame(command: 2, p1: 8, p2: 1, payload: Data([enabled ? 1 : 0]))
    }

    static func timeWeather(_ enabled: Bool) -> Data {
        HudProtocol.frame(command: 2, p1: 9, p2: 4, payload: Data([enabled ? 1 : 0]))
    }


    // MARK: - HUD notification / ANCS display configuration

    static func notificationSettingsInit() -> Data {
        HudProtocol.frame(command: 2, p1: 9, p2: 6)
    }

    static func notificationsMasterEnabled(_ enabled: Bool) -> Data {
        HudProtocol.frame(
            command: 2, p1: 9, p2: 7,
            payload: Data([enabled ? 1 : 0])
        )
    }

    static func notificationFilter(
        enabled: Bool,
        textColor: Int32 = -1,
        icon: Int32 = 0,
        identifiers: [String]
    ) -> Data {
        var payload = Data([enabled ? 1 : 0])
        payload.append(HudProtocol.int32(textColor))
        payload.append(HudProtocol.int32(icon))
        payload.append(HudProtocol.int32(Int32(identifiers.count)))
        for identifier in identifiers {
            payload.append(HudProtocol.javaWriteUTF(identifier))
        }
        return HudProtocol.frame(command: 2, p1: 9, p2: 8, payload: payload)
    }

    static func notificationTimeout(seconds: Int) -> Data {
        HudProtocol.frame(
            command: 2, p1: 9, p2: 1,
            payload: HudProtocol.int32(Int32(max(1, seconds)))
        )
    }

    static func notificationLineCount(_ count: Int) -> Data {
        HudProtocol.frame(
            command: 2, p1: 116, p2: 0,
            payload: HudProtocol.int32(Int32(max(1, count)))
        )
    }

    static func phoneName(_ name: String) -> Data {
        HudProtocol.frame(command: 2, p1: 123, p2: 0, payload: HudProtocol.javaWriteUTF(name))
    }

    static func systemTime(date: Date = Date(), timezone: TimeZone = .current) -> Data {
        var payload = HudProtocol.int64(Int64(date.timeIntervalSince1970 * 1000))
        payload.append(HudProtocol.javaWriteUTF(timezone.identifier))
        return HudProtocol.frame(command: 2, p1: 1, p2: 0, payload: payload)
    }

    static func dashboard(left: String, center: String, right: String, navigationLayout: Bool) -> Data {
        var payload = HudProtocol.javaWriteUTF(left)
        payload.append(HudProtocol.javaWriteUTF(center))
        payload.append(HudProtocol.javaWriteUTF(right))
        payload.append(HudProtocol.int32(navigationLayout ? 1 : 0))
        return HudProtocol.frame(command: 2, p1: 111, p2: 0, payload: payload)
    }

    static func maneuver(_ instruction: NavigationInstruction) -> Data {
        let text = [instruction.primaryText, instruction.streetName, instruction.currentStreet]
            .joined(separator: "\n")
        var payload = HudProtocol.javaWriteUTF(text)
        payload.append(HudProtocol.int32(Int32(instruction.maneuver.type)))
        payload.append(HudProtocol.int32(Int32(instruction.maneuver.direction)))
        payload.append(HudProtocol.int32(Int32(max(0, instruction.distanceMeters))))
        payload.append(HudProtocol.int32(0))
        payload.append(HudProtocol.int32(0))
        payload.append(HudProtocol.int32(Int32(instruction.exitNumber ?? 0)))
        payload.append(1) // right-side driving
        return HudProtocol.frame(command: 2, p1: 100, p2: 1, payload: payload)
    }
}

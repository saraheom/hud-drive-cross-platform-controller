import Foundation

enum HudwayCommands {
    static func uartConnectionCheck() -> Data { HudwayProtocol.frame(command: 2, p1: 6, p2: 0) }
    static func keepAlive() -> Data { HudwayProtocol.frame(command: 2, p1: 15, p2: 0) }

    static func navigationState(_ enabled: Bool) -> Data {
        HudwayProtocol.frame(command: 2, p1: 101, p2: 0, payload: HudwayProtocol.int32(enabled ? 1 : 0))
    }

    static func autoBrightness(_ enabled: Bool) -> Data {
        HudwayProtocol.frame(command: 2, p1: 2, p2: 1, payload: Data([enabled ? 1 : 0]))
    }

    static func manualBrightness(_ value: Int) -> Data {
        let clamped = max(0, min(100, value))
        var payload = HudwayProtocol.int32(Int32(clamped))
        payload.append(0)
        return HudwayProtocol.frame(command: 2, p1: 2, p2: 4, payload: payload)
    }

    static func fullScreen(_ enabled: Bool) -> Data {
        HudwayProtocol.frame(command: 2, p1: 8, p2: 1, payload: Data([enabled ? 1 : 0]))
    }

    static func timeWeather(_ enabled: Bool) -> Data {
        HudwayProtocol.frame(command: 2, p1: 9, p2: 4, payload: Data([enabled ? 1 : 0]))
    }


    // MARK: - HUD notification / ANCS display configuration

    static func notificationSettingsInit() -> Data {
        HudwayProtocol.frame(command: 2, p1: 9, p2: 6)
    }

    static func notificationsMasterEnabled(_ enabled: Bool) -> Data {
        HudwayProtocol.frame(
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
        payload.append(HudwayProtocol.int32(textColor))
        payload.append(HudwayProtocol.int32(icon))
        payload.append(HudwayProtocol.int32(Int32(identifiers.count)))
        for identifier in identifiers {
            payload.append(HudwayProtocol.javaWriteUTF(identifier))
        }
        return HudwayProtocol.frame(command: 2, p1: 9, p2: 8, payload: payload)
    }

    static func notificationTimeout(seconds: Int) -> Data {
        HudwayProtocol.frame(
            command: 2, p1: 9, p2: 1,
            payload: HudwayProtocol.int32(Int32(max(1, seconds)))
        )
    }

    static func notificationLineCount(_ count: Int) -> Data {
        HudwayProtocol.frame(
            command: 2, p1: 116, p2: 0,
            payload: HudwayProtocol.int32(Int32(max(1, count)))
        )
    }

    static func phoneName(_ name: String) -> Data {
        HudwayProtocol.frame(command: 2, p1: 123, p2: 0, payload: HudwayProtocol.javaWriteUTF(name))
    }

    static func systemTime(date: Date = Date(), timezone: TimeZone = .current) -> Data {
        var payload = HudwayProtocol.int64(Int64(date.timeIntervalSince1970 * 1000))
        payload.append(HudwayProtocol.javaWriteUTF(timezone.identifier))
        return HudwayProtocol.frame(command: 2, p1: 1, p2: 0, payload: payload)
    }

    static func dashboard(left: String, center: String, right: String, navigationLayout: Bool) -> Data {
        var payload = HudwayProtocol.javaWriteUTF(left)
        payload.append(HudwayProtocol.javaWriteUTF(center))
        payload.append(HudwayProtocol.javaWriteUTF(right))
        payload.append(HudwayProtocol.int32(navigationLayout ? 1 : 0))
        return HudwayProtocol.frame(command: 2, p1: 111, p2: 0, payload: payload)
    }

    static func maneuver(_ instruction: NavigationInstruction) -> Data {
        let text = [instruction.primaryText, instruction.streetName, instruction.currentStreet]
            .joined(separator: "\n")
        var payload = HudwayProtocol.javaWriteUTF(text)
        payload.append(HudwayProtocol.int32(Int32(instruction.maneuver.type)))
        payload.append(HudwayProtocol.int32(Int32(instruction.maneuver.direction)))
        payload.append(HudwayProtocol.int32(Int32(max(0, instruction.distanceMeters))))
        payload.append(HudwayProtocol.int32(0))
        payload.append(HudwayProtocol.int32(0))
        payload.append(HudwayProtocol.int32(Int32(instruction.exitNumber ?? 0)))
        payload.append(1) // right-side driving
        return HudwayProtocol.frame(command: 2, p1: 100, p2: 1, payload: payload)
    }
}

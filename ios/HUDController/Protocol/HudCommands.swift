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

    /// Original HUDWAY `HudBaseColorCommandPacket`:
    /// CommandPacket(p1=120, p2=0), payload = DataOutputStream.writeUTF(color).
    static func baseColor(_ theme: HudColorTheme) -> Data {
        HudProtocol.frame(
            command: 2,
            p1: 120,
            p2: 0,
            payload: HudProtocol.javaWriteUTF(theme.originalWireValue)
        )
    }

    static func timeWeather(_ enabled: Bool) -> Data {
        HudProtocol.frame(command: 2, p1: 9, p2: 4, payload: Data([enabled ? 1 : 0]))
    }


    /// Original decompiled DisplaySpeedUintsCommandPacket:
    /// CommandPacket(p1=9, p2=5), payload=int32 unit type.
    /// Original HUDWAY settings: 0 = metric (km), 1 = imperial (miles).
    ///
    /// Despite the class name, the stock app's settings provider uses this
    /// same unitType for the HUD's distance/mileage presentation.
    static func displayUnits(_ type: Int32) -> Data {
        HudProtocol.frame(
            command: 2,
            p1: 9,
            p2: 5,
            payload: HudProtocol.int32(type)
        )
    }

    static func imperialUnits() -> Data {
        displayUnits(1)
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

    /// Original HUDWAY `HudEtaPacket`: CommandPacket(p1=114, p2=0),
    /// payload = DataOutputStream.writeLong(absolute ETA milliseconds).
    static func eta(arrivalTimeMilliseconds: Int64) -> Data {
        HudProtocol.frame(
            command: 2,
            p1: 114,
            p2: 0,
            payload: HudProtocol.int64(arrivalTimeMilliseconds)
        )
    }

    static func dashboard(left: String, center: String, right: String, navigationLayout: Bool) -> Data {
        var payload = HudProtocol.javaWriteUTF(left)
        payload.append(HudProtocol.javaWriteUTF(center))
        payload.append(HudProtocol.javaWriteUTF(right))
        payload.append(HudProtocol.int32(navigationLayout ? 1 : 0))
        return HudProtocol.frame(command: 2, p1: 111, p2: 0, payload: payload)
    }

    static func maneuver(_ instruction: NavigationInstruction) -> Data {
        // v90.32 restores the original HUDWAY presentation. The native maneuver
        // packet already carries distanceMeters as its dedicated Int32 distance
        // field, so do not duplicate the source distance in the first text line.
        // `displayDistanceText` remains available to diagnostics and source
        // comparison, but the physical HUD text is simply e.g. "Turn right".
        let text = [
            instruction.primaryText,
            instruction.streetName,
            instruction.currentStreet
        ]
        .filter { !$0.isEmpty }
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

    // MARK: - Original vehicle integration packets

    /// Decompiled Android OBDIIInternalPacket:
    /// InternalPacket(command=0, p1=7, p2=1)
    /// payload = boolean connect + int32 obdType + DataOutputStream.writeUTF(name)
    static func obdConnection(enabled: Bool, deviceName: String = "OBDII", obdType: Int32 = 0) -> Data {
        var payload = Data([enabled ? 1 : 0])
        payload.append(HudProtocol.int32(obdType))
        payload.append(HudProtocol.javaWriteUTF(deviceName))
        return HudProtocol.frame(command: 0, p1: 7, p2: 1, payload: payload)
    }

    /// Decompiled OBDIICustomItemInternalPacket:
    /// InternalPacket(command=0, p1=7, p2=2)
    /// payload = int32 position + int32 ObdItemType ordinal
    static func obdCustomItem(position: Int32, itemIndex: Int32) -> Data {
        var payload = HudProtocol.int32(position)
        payload.append(HudProtocol.int32(itemIndex))
        return HudProtocol.frame(command: 0, p1: 7, p2: 2, payload: payload)
    }

    /// Decompiled SpeedNotificationPacket (Notification category 14).
    static func speedNotification(kmh: Int) -> Data {
        notificationPacket(
            category: 14,
            packageName: "",
            title: String(max(0, kmh)),
            message: ""
        )
    }

    /// Decompiled MusicNotificationPacket (Notification category 12).
    static func musicNotification(artist: String, track: String, packageName: String = "com.kivic.music") -> Data {
        notificationPacket(
            category: 12,
            packageName: packageName,
            title: artist,
            message: track
        )
    }

    private static func notificationPacket(
        category: UInt8,
        packageName: String,
        title: String,
        message: String
    ) -> Data {
        var payload = HudProtocol.javaWriteUTF(packageName)
        payload.append(HudProtocol.javaNotificationString(title))
        payload.append(HudProtocol.javaNotificationString(message))
        return HudProtocol.frame(command: 1, p1: category, p2: 0, payload: payload)
    }

    /// Decompiled HudSpeedLimitAndToleranceCommandPacket
    /// CommandPacket(command=2, p1=101, p2=2)
    static func speedLimit(limit: Int, tolerance: Int = 0) -> Data {
        var payload = HudProtocol.int32(Int32(max(0, limit)))
        payload.append(HudProtocol.int32(Int32(max(0, tolerance))))
        // v47: the app intentionally supports only the rectangular U.S.-style
        // speed-limit sign. Never transmit the circular-style flag.
        payload.append(HudProtocol.int32(1))
        return HudProtocol.frame(command: 2, p1: 101, p2: 2, payload: payload)
    }

    /// Decompiled DisplaySpeedWarningCommandPacket(command=2, p1=9, p2=9)
    static func speedWarningThreshold(_ value: Int) -> Data {
        HudProtocol.frame(
            command: 2, p1: 9, p2: 9,
            payload: HudProtocol.int32(Int32(max(0, value)))
        )
    }


    /// Original DisplayNotificationSettingCommandPacket.getDefaultMusicSettingPacket()
    /// package=com.kivic.music, icon=3, textColor=-12996114.
    static func musicNotificationFilter(enabled: Bool) -> Data {
        notificationFilter(
            enabled: enabled,
            textColor: -12996114,
            icon: 3,
            identifiers: ["com.kivic.music"]
        )
    }





    // MARK: - Experimental hidden display commands

    /// Decompiled PushMessageCommandPacket:
    /// CommandPacket(command=2, p1=24/ASCII CAN, p2=0)
    /// payload = int32 Display_Position + int32 Display_type +
    ///           Java writeUTF(title) + Java writeUTF(message)
    ///
    /// Display_Position ordinals:
    /// 0 TOP, 1 LEFT, 2 DOWN, 3 FULL
    /// Display_type ordinals:
    /// 0 INFO, 1 WARNING
    static func pushMessage(
        position: Int32,
        type: Int32 = 0,
        title: String,
        message: String
    ) -> Data {
        var payload = HudProtocol.int32(position)
        payload.append(HudProtocol.int32(type))
        payload.append(HudProtocol.javaWriteUTF(title))
        payload.append(HudProtocol.javaWriteUTF(message))
        return HudProtocol.frame(command: 2, p1: 24, p2: 0, payload: payload)
    }

    /// Decompiled HudHUDWidgetsMiniState(command=2, p1=122, p2=0).
    static func widgetsMiniState(_ enabled: Bool) -> Data {
        HudProtocol.frame(
            command: 2,
            p1: 122,
            p2: 0,
            payload: Data([enabled ? 1 : 0])
        )
    }

}

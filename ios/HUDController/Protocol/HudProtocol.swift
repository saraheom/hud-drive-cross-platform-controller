import Foundation

enum HudProtocol {
    static let serviceUUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    static let writeUUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    static let notifyUUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

    static let stx: UInt8 = 0x02
    static let etx: UInt8 = 0x03
    static let esc: UInt8 = 0x7D
    static let chunkSize = 19

    static func frame(command: UInt8, p1: UInt8, p2: UInt8, payload: Data = Data()) -> Data {
        var body = Data([command, p1, p2])
        body.append(payload)
        var result = Data([stx])
        for byte in body {
            if byte == stx || byte == etx || byte == esc {
                result.append(esc)
                result.append(byte ^ esc)
            } else {
                result.append(byte)
            }
        }
        result.append(etx)
        return result
    }

    static func int32(_ value: Int32) -> Data {
        let u = UInt32(bitPattern: value).bigEndian
        return withUnsafeBytes(of: u) { Data($0) }
    }

    static func int64(_ value: Int64) -> Data {
        let u = UInt64(bitPattern: value).bigEndian
        return withUnsafeBytes(of: u) { Data($0) }
    }

    static func uint16(_ value: UInt16) -> Data {
        let u = value.bigEndian
        return withUnsafeBytes(of: u) { Data($0) }
    }

    /// NotificationPacket writes title/message as UTF-8 bytes preceded by
    /// unsigned-short byte counts (packageName itself uses Java writeUTF).
    static func javaNotificationString(_ string: String) -> Data {
        let bytes = Data(string.utf8)
        precondition(bytes.count <= 65535, "notification string too long")
        var result = uint16(UInt16(bytes.count))
        result.append(bytes)
        return result
    }

    /// Java DataOutputStream.writeUTF-compatible Modified UTF-8 for BMP/non-BMP strings.
    static func javaWriteUTF(_ string: String) -> Data {
        var encoded = Data()
        for unit in string.utf16 {
            switch unit {
            case 0x0001...0x007F:
                encoded.append(UInt8(unit))
            case 0x0000...0x07FF:
                encoded.append(UInt8(0xC0 | ((unit >> 6) & 0x1F)))
                encoded.append(UInt8(0x80 | (unit & 0x3F)))
            default:
                encoded.append(UInt8(0xE0 | ((unit >> 12) & 0x0F)))
                encoded.append(UInt8(0x80 | ((unit >> 6) & 0x3F)))
                encoded.append(UInt8(0x80 | (unit & 0x3F)))
            }
        }
        precondition(encoded.count <= 65535, "writeUTF payload too long")
        var result = Data()
        let length = UInt16(encoded.count).bigEndian
        withUnsafeBytes(of: length) { result.append(contentsOf: $0) }
        result.append(encoded)
        return result
    }

    static func chunks(_ data: Data) -> [Data] {
        stride(from: 0, to: data.count, by: chunkSize).map {
            data.subdata(in: $0..<min($0 + chunkSize, data.count))
        }
    }

    static func unescape(_ packet: Data) -> Data? {
        guard packet.count >= 2, packet.first == stx, packet.last == etx else { return nil }
        let bytes = [UInt8](packet)
        var out = Data()
        var i = 1
        while i < bytes.count - 1 {
            if bytes[i] == esc {
                i += 1
                guard i < bytes.count - 1 else { return nil }
                out.append(bytes[i] ^ esc)
            } else {
                out.append(bytes[i])
            }
            i += 1
        }
        return out
    }

    static func extractFrames(from buffer: inout Data) -> [Data] {
        var frames: [Data] = []
        while true {
            guard let stxIndex = buffer.firstIndex(of: stx) else {
                buffer.removeAll()
                break
            }
            if stxIndex > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<stxIndex)
            }
            guard let etxIndex = buffer.dropFirst().firstIndex(of: etx) else { break }
            let endExclusive = buffer.index(after: etxIndex)
            let frame = buffer.subdata(in: buffer.startIndex..<endExclusive)
            frames.append(frame)
            buffer.removeSubrange(buffer.startIndex..<endExclusive)
        }
        return frames
    }

    static func isUARTConnectionEvent(_ packet: Data) -> Bool {
        guard let body = unescape(packet), body.count >= 3 else { return false }
        return body[0] == 3 && body[1] == 1 && body[2] == 1
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

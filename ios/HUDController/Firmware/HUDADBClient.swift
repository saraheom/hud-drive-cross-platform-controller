import Foundation
import Network
import CryptoKit

actor HUDADBClient {
    enum ADBError: LocalizedError {
        case notConnected
        case connectionFailed(String)
        case protocolError(String)
        case authRequired
        case unexpectedTarget(String)
        case serviceClosed(String)
        case syncFailed(String)
        case fileReadFailed

        var errorDescription: String? {
            switch self {
            case .notConnected: return "ADB is not connected."
            case .connectionFailed(let detail): return "ADB connection failed: \(detail)"
            case .protocolError(let detail): return "ADB protocol error: \(detail)"
            case .authRequired: return "HUD requested ADB authentication even though this firmware was measured with ro.adb.secure=0."
            case .unexpectedTarget(let detail): return "ADB target verification failed: \(detail)"
            case .serviceClosed(let detail): return "ADB service closed: \(detail)"
            case .syncFailed(let detail): return "ADB file transfer failed: \(detail)"
            case .fileReadFailed: return "Could not read the selected local file."
            }
        }
    }

    struct RemoteHashResult: Sendable {
        let byteCount: Int64
        let sha256: String
    }

    private struct Packet {
        let command: UInt32
        let arg0: UInt32
        let arg1: UInt32
        let payload: Data
    }

    private struct StreamHandle {
        let localID: UInt32
        let remoteID: UInt32
    }

    private var connection: NWConnection?
    private var serverMaxData = 4096
    private var nextLocalID: UInt32 = 1
    private let queue = DispatchQueue(label: "HUDController.ADB")

    private static let cnxn = command("CNXN")
    private static let auth = command("AUTH")
    private static let open = command("OPEN")
    private static let okay = command("OKAY")
    private static let clse = command("CLSE")
    private static let wrte = command("WRTE")

    var isConnected: Bool { connection != nil }

    func connect(host: String = "192.168.43.1", port: UInt16 = 5555) async throws {
        disconnect()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ADBError.connectionFailed("Invalid port \(port)")
        }

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        try await waitForReady(conn)
        connection = conn

        let banner = Data("host::\0".utf8)
        try await sendPacket(command: Self.cnxn, arg0: 0x01000000, arg1: 4096, payload: banner)

        while true {
            let packet = try await readPacket()
            if packet.command == Self.cnxn {
                serverMaxData = max(1024, Int(packet.arg1))
                return
            }
            if packet.command == Self.auth {
                disconnect()
                throw ADBError.authRequired
            }
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        serverMaxData = 4096
    }

    func shell(_ command: String) async throws -> String {
        let stream = try await openService("shell:\(command)")
        var output = Data()
        while true {
            let result = try await receiveStreamChunk(stream)
            if result.closed { break }
            output.append(result.data)
        }
        return String(data: output, encoding: .utf8) ?? String(decoding: output, as: UTF8.self)
    }

    func reboot() async throws {
        _ = try await openService("reboot:")
        connection?.cancel()
        connection = nil
    }

    func push(localURL: URL,
              remotePath: String,
              mode: UInt32 = 0o100644,
              progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws {
        guard FileManager.default.fileExists(atPath: localURL.path) else { throw ADBError.fileReadFailed }
        let attrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let total = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard let handle = try? FileHandle(forReadingFrom: localURL) else { throw ADBError.fileReadFailed }
        defer { try? handle.close() }

        let stream = try await openService("sync:")
        var pendingInbound = Data()
        let sendSpec = "\(remotePath),\(mode)"
        try await sendStreamData(syncRecord(id: "SEND", payload: Data(sendSpec.utf8)), stream: stream, pendingInbound: &pendingInbound)

        let chunkSize = max(1024, min(64 * 1024, serverMaxData - 8))
        var sent: Int64 = 0
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            try await sendStreamData(syncRecord(id: "DATA", payload: chunk), stream: stream, pendingInbound: &pendingInbound)
            sent += Int64(chunk.count)
            progress?(sent, total)
        }

        var done = Data("DONE".utf8)
        done.appendLE(UInt32(Date().timeIntervalSince1970))
        try await sendStreamData(done, stream: stream, pendingInbound: &pendingInbound)

        let response = try await readSyncResponse(stream: stream, buffer: &pendingInbound)
        guard response.id == "OKAY" else {
            throw ADBError.syncFailed(response.message ?? response.id)
        }
        try? await closeStream(stream)
    }

    func hashRemoteFile(_ remotePath: String) async throws -> RemoteHashResult {
        let stream = try await openService("sync:")
        var pendingInbound = Data()
        try await sendStreamData(syncRecord(id: "RECV", payload: Data(remotePath.utf8)), stream: stream, pendingInbound: &pendingInbound)

        var hasher = SHA256()
        var count: Int64 = 0
        var buffer = pendingInbound

        while true {
            try await ensureSyncBytes(8, stream: stream, buffer: &buffer)
            let idData = buffer.prefix(4)
            let id = String(data: idData, encoding: .ascii) ?? "????"
            let value = readUInt32LE(buffer, offset: 4)
            buffer.removeFirst(8)

            switch id {
            case "DATA":
                let length = Int(value)
                try await ensureSyncBytes(length, stream: stream, buffer: &buffer)
                let chunk = Data(buffer.prefix(length))
                buffer.removeFirst(length)
                hasher.update(data: chunk)
                count += Int64(length)
            case "DONE":
                try? await closeStream(stream)
                let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                return RemoteHashResult(byteCount: count, sha256: digest)
            case "FAIL":
                let length = Int(value)
                try await ensureSyncBytes(length, stream: stream, buffer: &buffer)
                let message = String(data: buffer.prefix(length), encoding: .utf8) ?? "remote FAIL"
                throw ADBError.syncFailed(message)
            default:
                throw ADBError.protocolError("Unexpected SYNC record \(id)")
            }
        }
    }

    private func waitForReady(_ conn: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let lock = NSLock()
            var finished = false
            func finish(_ result: Result<Void, Error>) {
                lock.lock(); defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                conn.stateUpdateHandler = nil
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.success(()))
                case .failed(let error):
                    finish(.failure(ADBError.connectionFailed(error.localizedDescription)))
                case .cancelled:
                    finish(.failure(ADBError.connectionFailed("Connection cancelled")))
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
    }

    private func openService(_ service: String) async throws -> StreamHandle {
        guard connection != nil else { throw ADBError.notConnected }
        let localID = nextLocalID
        nextLocalID &+= 1
        if nextLocalID == 0 { nextLocalID = 1 }
        var payload = Data(service.utf8)
        payload.append(0)
        try await sendPacket(command: Self.open, arg0: localID, arg1: 0, payload: payload)

        while true {
            let packet = try await readPacket()
            if packet.command == Self.okay, packet.arg1 == localID {
                return StreamHandle(localID: localID, remoteID: packet.arg0)
            }
            if packet.command == Self.clse, packet.arg1 == localID {
                throw ADBError.serviceClosed(service)
            }
            if packet.command == Self.wrte, packet.arg1 == localID {
                try await sendPacket(command: Self.okay, arg0: localID, arg1: packet.arg0, payload: Data())
            }
        }
    }

    private func closeStream(_ stream: StreamHandle) async throws {
        try await sendPacket(command: Self.clse, arg0: stream.localID, arg1: stream.remoteID, payload: Data())
    }

    private func sendStreamData(_ data: Data,
                                stream: StreamHandle,
                                pendingInbound: inout Data) async throws {
        try await sendPacket(command: Self.wrte, arg0: stream.localID, arg1: stream.remoteID, payload: data)
        while true {
            let packet = try await readPacket()
            if packet.command == Self.okay,
               packet.arg0 == stream.remoteID,
               packet.arg1 == stream.localID {
                return
            }
            if packet.command == Self.wrte,
               packet.arg0 == stream.remoteID,
               packet.arg1 == stream.localID {
                pendingInbound.append(packet.payload)
                try await sendPacket(command: Self.okay, arg0: stream.localID, arg1: stream.remoteID, payload: Data())
                continue
            }
            if packet.command == Self.clse, packet.arg1 == stream.localID {
                throw ADBError.serviceClosed("stream \(stream.localID)")
            }
        }
    }

    private func receiveStreamChunk(_ stream: StreamHandle) async throws -> (data: Data, closed: Bool) {
        while true {
            let packet = try await readPacket()
            if packet.command == Self.wrte,
               packet.arg0 == stream.remoteID,
               packet.arg1 == stream.localID {
                try await sendPacket(command: Self.okay, arg0: stream.localID, arg1: stream.remoteID, payload: Data())
                return (packet.payload, false)
            }
            if packet.command == Self.clse, packet.arg1 == stream.localID {
                try? await sendPacket(command: Self.clse, arg0: stream.localID, arg1: stream.remoteID, payload: Data())
                return (Data(), true)
            }
        }
    }

    private func ensureSyncBytes(_ count: Int,
                                 stream: StreamHandle,
                                 buffer: inout Data) async throws {
        while buffer.count < count {
            let result = try await receiveStreamChunk(stream)
            if result.closed { throw ADBError.serviceClosed("sync") }
            buffer.append(result.data)
        }
    }

    private func readSyncResponse(stream: StreamHandle,
                                  buffer: inout Data) async throws -> (id: String, message: String?) {
        try await ensureSyncBytes(8, stream: stream, buffer: &buffer)
        let id = String(data: buffer.prefix(4), encoding: .ascii) ?? "????"
        let value = Int(readUInt32LE(buffer, offset: 4))
        buffer.removeFirst(8)
        if id == "FAIL" {
            try await ensureSyncBytes(value, stream: stream, buffer: &buffer)
            let message = String(data: buffer.prefix(value), encoding: .utf8)
            return (id, message)
        }
        return (id, nil)
    }

    private func syncRecord(id: String, payload: Data) -> Data {
        var data = Data(id.utf8)
        data.appendLE(UInt32(payload.count))
        data.append(payload)
        return data
    }

    private func sendPacket(command: UInt32, arg0: UInt32, arg1: UInt32, payload: Data) async throws {
        guard let connection else { throw ADBError.notConnected }
        var data = Data()
        data.appendLE(command)
        data.appendLE(arg0)
        data.appendLE(arg1)
        data.appendLE(UInt32(payload.count))
        data.appendLE(payload.reduce(UInt32(0)) { $0 &+ UInt32($1) })
        data.appendLE(command ^ 0xffffffff)
        data.append(payload)
        try await send(data, over: connection)
    }

    private func readPacket() async throws -> Packet {
        guard let connection else { throw ADBError.notConnected }
        let header = try await receiveExactly(24, over: connection)
        let command = readUInt32LE(header, offset: 0)
        let arg0 = readUInt32LE(header, offset: 4)
        let arg1 = readUInt32LE(header, offset: 8)
        let length = Int(readUInt32LE(header, offset: 12))
        let checksum = readUInt32LE(header, offset: 16)
        let magic = readUInt32LE(header, offset: 20)
        guard magic == (command ^ 0xffffffff) else {
            throw ADBError.protocolError("Bad message magic")
        }
        guard length >= 0, length <= 16 * 1024 * 1024 else {
            throw ADBError.protocolError("Implausible payload length \(length)")
        }
        let payload = length == 0 ? Data() : try await receiveExactly(length, over: connection)
        if checksum != 0 {
            let actual = payload.reduce(UInt32(0)) { $0 &+ UInt32($1) }
            guard actual == checksum else { throw ADBError.protocolError("Payload checksum mismatch") }
        }
        return Packet(command: command, arg0: arg0, arg1: arg1, payload: payload)
    }

    private func send(_ data: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: ADBError.connectionFailed(error.localizedDescription)) }
                else { continuation.resume() }
            })
        }
    }

    private func receiveExactly(_ count: Int, over connection: NWConnection) async throws -> Data {
        var result = Data()
        while result.count < count {
            let chunk: Data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: count - result.count) { data, _, complete, error in
                    if let error {
                        continuation.resume(throwing: ADBError.connectionFailed(error.localizedDescription))
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if complete {
                        continuation.resume(throwing: ADBError.connectionFailed("Remote closed connection"))
                    } else {
                        continuation.resume(throwing: ADBError.connectionFailed("Empty receive"))
                    }
                }
            }
            result.append(chunk)
        }
        return result
    }

    private static func command(_ text: String) -> UInt32 {
        let bytes = Array(text.utf8)
        precondition(bytes.count == 4)
        return UInt32(bytes[0]) |
            (UInt32(bytes[1]) << 8) |
            (UInt32(bytes[2]) << 16) |
            (UInt32(bytes[3]) << 24)
    }

    private func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        let bytes = [UInt8](data[offset..<(offset + 4)])
        return UInt32(bytes[0]) |
            (UInt32(bytes[1]) << 8) |
            (UInt32(bytes[2]) << 16) |
            (UInt32(bytes[3]) << 24)
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}

import Foundation
import Network
import Darwin

/// Minimal KivicCast-compatible network responder for the physical HUDWAY Drive.
///
/// The recovered HudLauncher viewer broadcasts `KVMJPEG/1.0`, accepts a JSON
/// stream descriptor and supports an HTTP Motion-JPEG source. The server is
/// intentionally read-only from the HUD's perspective: it listens for discovery
/// and serves frames; it never writes the HUD filesystem or firmware.
final class HudMapModeCastServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "HUD.MapMode.CastServer")
    private let frameLock = NSLock()
    private var latestJPEG: Data?
    private var tcpListener: NWListener?
    private var udpListener: NWListener?
    private var clients: [ObjectIdentifier: NWConnection] = [:]
    private var running = false

    var onEvent: (@Sendable (String) -> Void)?

    func updateFrame(_ jpeg: Data) {
        frameLock.lock()
        latestJPEG = jpeg
        frameLock.unlock()
    }

    func start() throws {
        guard !running else { return }
        running = true

        let tcpPort = NWEndpoint.Port(rawValue: 15330)!
        let udpPort = NWEndpoint.Port(rawValue: 15320)!

        let tcp = try NWListener(using: .tcp, on: tcpPort)
        tcp.newConnectionHandler = { [weak self] connection in
            self?.acceptHTTP(connection)
        }
        tcp.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onEvent?("MJPEG HTTP server ready on port 15330")
            case .failed(let error):
                self?.onEvent?("MJPEG HTTP server failed: \(error.localizedDescription)")
            default:
                break
            }
        }
        tcp.start(queue: queue)
        tcpListener = tcp

        let udp = try NWListener(using: .udp, on: udpPort)
        udp.newConnectionHandler = { [weak self] connection in
            self?.acceptDiscovery(connection)
        }
        udp.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onEvent?("KivicCast discovery ready on UDP 15320")
            case .failed(let error):
                self?.onEvent?("KivicCast discovery failed: \(error.localizedDescription)")
            default:
                break
            }
        }
        udp.start(queue: queue)
        udpListener = udp

        onEvent?("Map Mode cast server started")
    }

    func stop() {
        guard running else { return }
        running = false
        tcpListener?.cancel()
        udpListener?.cancel()
        tcpListener = nil
        udpListener = nil
        for connection in clients.values { connection.cancel() }
        clients.removeAll()
        onEvent?("Map Mode cast server stopped")
    }

    private func acceptDiscovery(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            if case .ready = state {
                self.receiveDiscovery(on: connection)
            }
        }
        connection.start(queue: queue)
    }

    private func receiveDiscovery(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            guard let self, let connection else { return }
            if let data,
               let text = String(data: data, encoding: .utf8),
               text.contains("KVMJPEG/1.0") {
                let ip = Self.localIPv4Address() ?? "192.168.43.195"
                let descriptor: [String: Any] = [
                    "streamType": "http",
                    "streamURL": "http://\(ip):15330",
                    "ip": ip,
                    "port": 15330,
                    "fps": 5,
                    "timeout": 5000
                ]
                if let payload = try? JSONSerialization.data(withJSONObject: descriptor) {
                    connection.send(content: payload, completion: .contentProcessed { [weak self] sendError in
                        if let sendError {
                            self?.onEvent?("KivicCast discovery reply failed: \(sendError.localizedDescription)")
                        } else {
                            self?.onEvent?("HUD discovered Map Mode stream at \(ip):15330")
                        }
                    })
                }
            }
            if error == nil, self.running {
                self.receiveDiscovery(on: connection)
            } else {
                connection.cancel()
            }
        }
    }

    private func acceptHTTP(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        clients[id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.readHTTPRequest(on: connection, id: id)
            case .failed(_), .cancelled:
                self.clients.removeValue(forKey: id)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func readHTTPRequest(on connection: NWConnection, id: ObjectIdentifier) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak connection] _, _, _, error in
            guard let self, let connection else { return }
            guard error == nil else {
                self.clients.removeValue(forKey: id)
                connection.cancel()
                return
            }

            let header = "HTTP/1.1 200 OK\r\n" +
                "Connection: close\r\n" +
                "Cache-Control: no-cache, no-store, must-revalidate\r\n" +
                "Pragma: no-cache\r\n" +
                "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n\r\n"
            connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] sendError in
                guard let self else { return }
                if let sendError {
                    self.onEvent?("MJPEG response failed: \(sendError.localizedDescription)")
                    self.clients.removeValue(forKey: id)
                    connection.cancel()
                    return
                }
                self.onEvent?("HUD MJPEG client streaming")
                self.sendNextFrame(on: connection, id: id)
            })
        }
    }

    private func sendNextFrame(on connection: NWConnection, id: ObjectIdentifier) {
        guard running, clients[id] != nil else { return }

        frameLock.lock()
        let frame = latestJPEG
        frameLock.unlock()

        guard let frame else {
            queue.asyncAfter(deadline: .now() + 0.20) { [weak self, weak connection] in
                guard let self, let connection else { return }
                self.sendNextFrame(on: connection, id: id)
            }
            return
        }

        var packet = Data("--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(frame.count)\r\n\r\n".utf8)
        packet.append(frame)
        packet.append(Data("\r\n".utf8))

        connection.send(content: packet, completion: .contentProcessed { [weak self, weak connection] error in
            guard let self, let connection else { return }
            if let error {
                self.onEvent?("MJPEG client closed: \(error.localizedDescription)")
                self.clients.removeValue(forKey: id)
                connection.cancel()
                return
            }
            self.queue.asyncAfter(deadline: .now() + 0.20) { [weak self, weak connection] in
                guard let self, let connection else { return }
                self.sendNextFrame(on: connection, id: id)
            }
        })
    }

    private static func localIPv4Address() -> String? {
        var address: String?
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let interface = current.pointee
            guard let sa = interface.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name.hasPrefix("en") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                sa,
                socklen_t(sa.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let value = String(cString: host)
                if value != "127.0.0.1" {
                    address = value
                    if value.hasPrefix("192.168.43.") { return value }
                }
            }
        }
        return address
    }
}

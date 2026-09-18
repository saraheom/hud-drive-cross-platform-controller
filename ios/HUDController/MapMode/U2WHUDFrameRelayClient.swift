import Foundation
import Network
import Observation

/// Persistent iPhone -> U2W JPEG ingress used by the live Map Mode relay.
/// Wire format on TCP/15331 is [u32 big-endian length][JPEG bytes].
///
/// v90.35.3.21 keeps this transport self-healing: if the adapter-side ingress
/// closes or a send fails, the iPhone reconnects automatically instead of
/// leaving the physical HUD frozen on its last successfully delivered frame.
@MainActor
@Observable
final class U2WHUDFrameRelayClient {
    private let logger: LogManager
    private let queue = DispatchQueue(label: "HUD.U2W.FrameRelay")
    private var connection: NWConnection?
    private var reconnectTask: Task<Void, Never>?
    private var shouldRun = false
    private var sendInFlight = false
    private(set) var connected = false
    private(set) var status = "Relay stopped"
    private(set) var sentFrameCount = 0
    private(set) var droppedFrameCount = 0
    private(set) var reconnectCount = 0
    private(set) var lastFrameBytes = 0

    init(logger: LogManager) {
        self.logger = logger
    }

    func start() {
        shouldRun = true
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        sendInFlight = false
        connected = false
        openConnection(reason: "start")
    }

    private func openConnection(reason: String) {
        guard shouldRun else { return }
        guard let port = NWEndpoint.Port(rawValue: 15331) else {
            status = "Invalid relay port"
            return
        }
        let c = NWConnection(host: "192.168.50.2", port: port, using: .tcp)
        connection = c
        connected = false
        status = "Connecting to U2W frame ingress…"
        logger.log("U2W RELAY", "Opening frame ingress 192.168.50.2:15331 reason=\(reason)")
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c else { return }
            Task { @MainActor in
                guard self.connection === c else { return }
                switch state {
                case .ready:
                    self.connected = true
                    self.status = "U2W frame ingress connected"
                    self.logger.log("U2W RELAY", "Frame ingress connected reconnects=\(self.reconnectCount)")
                case .failed(let error):
                    self.connected = false
                    self.status = "Relay failed: \(error.localizedDescription)"
                    self.logger.log("U2W RELAY", "Frame ingress failed: \(error.localizedDescription)")
                    self.scheduleReconnect(reason: "connection failed")
                case .cancelled:
                    self.connected = false
                    if self.shouldRun {
                        self.status = "Relay reconnecting…"
                        self.scheduleReconnect(reason: "connection cancelled")
                    } else {
                        self.status = "Relay stopped"
                    }
                default:
                    break
                }
            }
        }
        c.start(queue: queue)
    }

    private func scheduleReconnect(reason: String) {
        guard shouldRun, reconnectTask == nil else { return }
        let old = connection
        connection = nil
        old?.stateUpdateHandler = nil
        old?.cancel()
        connected = false
        sendInFlight = false
        reconnectCount += 1
        logger.log("U2W RELAY", "Scheduling ingress reconnect #\(reconnectCount) reason=\(reason)")
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, self.shouldRun else { return }
            self.reconnectTask = nil
            self.openConnection(reason: "auto-reconnect / \(reason)")
        }
    }

    func sendFrame(_ jpeg: Data) {
        guard connected, let c = connection else {
            droppedFrameCount += 1
            return
        }
        guard !sendInFlight else {
            droppedFrameCount += 1
            return
        }
        guard !jpeg.isEmpty, jpeg.count <= 131_072 else {
            droppedFrameCount += 1
            status = "Frame rejected (\(jpeg.count) bytes)"
            return
        }

        var len = UInt32(jpeg.count).bigEndian
        var packet = Data(bytes: &len, count: MemoryLayout<UInt32>.size)
        packet.append(jpeg)
        sendInFlight = true
        c.send(content: packet, completion: .contentProcessed { [weak self, weak c] error in
            guard let self, let c else { return }
            Task { @MainActor in
                guard self.connection === c else { return }
                self.sendInFlight = false
                if let error {
                    self.connected = false
                    self.status = "Relay send failed: \(error.localizedDescription)"
                    self.logger.log("U2W RELAY", "Frame send failed: \(error.localizedDescription)")
                    self.scheduleReconnect(reason: "send failed")
                    return
                }
                self.sentFrameCount += 1
                self.lastFrameBytes = jpeg.count
                if self.sentFrameCount == 1 || self.sentFrameCount % 50 == 0 {
                    self.logger.log(
                        "U2W RELAY",
                        "Sent frame #\(self.sentFrameCount) bytes=\(jpeg.count) dropped=\(self.droppedFrameCount) reconnects=\(self.reconnectCount)"
                    )
                }
            }
        })
    }

    func stop(reason: String = "manual") {
        shouldRun = false
        reconnectTask?.cancel()
        reconnectTask = nil
        let c = connection
        connection = nil
        c?.stateUpdateHandler = nil
        c?.cancel()
        sendInFlight = false
        connected = false
        status = "Relay stopped"
        logger.log("U2W RELAY", "Stopped reason=\(reason)")
    }
}

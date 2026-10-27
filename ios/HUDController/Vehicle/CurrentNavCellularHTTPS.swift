import Foundation
import Network

/// One-shot HTTPS request forced onto iPhone cellular when CarPlay's local-only
/// Wi-Fi prevents URLSession from reaching Overpass. Never used for local HUD
/// HTTP, media, or H.264. Uses normal TLS hostname validation through Network.
/// If cellular is unavailable the caller safely leaves the speed limit unknown.
enum CurrentNavCellularHTTPS {
    static func fetch(url: URL, timeout: TimeInterval = 12) async throws -> Data {
        guard url.scheme == "https", let host = url.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        let target = components.percentEncodedPath + components.percentEncodedQuery.map { "?" + $0 }.orEmpty
        let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? 443))!
        let parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
        parameters.requiredInterfaceType = .cellular
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        let request = "GET \(target.isEmpty ? "/" : target) HTTP/1.1\r\nHost: \(host)\r\nAccept: application/json\r\nAccept-Encoding: identity\r\nConnection: close\r\nUser-Agent: HUDController-CurrentNav/24.42\r\n\r\n"
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let transaction = Transaction(connection: connection, request: Data(request.utf8), continuation: continuation)
            transaction.start(timeout: timeout)
        }
    }

    private final class Transaction {
        let connection: NWConnection
        let request: Data
        var continuation: CheckedContinuation<Data, Error>?
        let queue = DispatchQueue(label: "HUD.CurrentNav.CellularHTTPS", qos: .utility)
        var bytes = Data()
        var completed = false

        init(connection: NWConnection, request: Data, continuation: CheckedContinuation<Data, Error>) {
            self.connection = connection
            self.request = request
            self.continuation = continuation
        }

        func start(timeout: TimeInterval) {
            connection.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    connection.send(content: request, completion: .contentProcessed { [self] error in
                        if let error { finish(.failure(error)) }
                        else { readMore() }
                    })
                case .failed(let error): finish(.failure(error))
                case .cancelled: finish(.failure(URLError(.cancelled)))
                default: break // waiting for a real cellular interface or TLS
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { [self] in
                finish(.failure(URLError(.timedOut)))
            }
        }

        func readMore() {
            guard !completed else { return }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] chunk, _, end, error in
                if let error { finish(.failure(error)); return }
                if let chunk { bytes.append(chunk) }
                guard bytes.count <= 10_000_000 else {
                    finish(.failure(URLError(.dataLengthExceedsMaximum))); return
                }
                if end {
                    do { finish(.success(try CurrentNavHTTPResponseParser.body(from: bytes))) }
                    catch { finish(.failure(error)) }
                } else {
                    readMore()
                }
            }
        }

        func finish(_ result: Result<Data, Error>) {
            guard !completed else { return }
            completed = true
            let pending = continuation
            continuation = nil
            connection.stateUpdateHandler = nil
            connection.cancel()
            pending?.resume(with: result)
        }
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}

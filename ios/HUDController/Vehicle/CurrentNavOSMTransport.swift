import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One small production transport shared by Current + Nav acquisition and its
/// deterministic network-response tests. It uses the *same* URLSession data(from:)
/// request policy as the original Current matcher, without an 11-second override.
/// Road identities and legal speeds are validated by the caller, never here.
enum CurrentNavOSMTransport {
    struct Result {
        let data: Data
        let statusCode: Int
    }

    static func download(url: URL, session: URLSession = .shared) async throws -> Result {
        let (data, response) = try await session.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return Result(data: data, statusCode: code)
    }
}

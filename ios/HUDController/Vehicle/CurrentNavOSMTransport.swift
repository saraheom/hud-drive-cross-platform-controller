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

    static func errorSummary(data: Data) -> String {
        guard let raw = String(data: data.prefix(3000), encoding: .utf8) else {
            return "non-UTF8 error body"
        }
        let withoutTags = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let oneLine = withoutTags.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        return String(oneLine.prefix(300))
    }

    static func download(url: URL, session: URLSession = .shared) async throws -> Result {
        let (data, response) = try await session.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return Result(data: data, statusCode: code)
    }
}

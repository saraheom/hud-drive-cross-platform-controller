import Foundation

/// Parses a small HTTPS/1.1 response returned by the opt-in cellular-only
/// Overpass connection. Normal URLSession requests do not use this parser.
/// Do not accept an error page or truncated JSON as a road-data response.
enum CurrentNavHTTPResponseParser {
    static func body(from wire: Data) throws -> Data {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = wire.range(of: separator) else { throw URLError(.cannotParseResponse) }
        let headers = String(decoding: wire[..<range.lowerBound], as: UTF8.self)
        guard let statusLine = headers.components(separatedBy: "\r\n").first,
              let codeString = statusLine.split(separator: " ").dropFirst().first,
              let code = Int(codeString), (200..<300).contains(code) else {
            throw URLError(.badServerResponse)
        }
        let bytes = Data(wire[range.upperBound...])
        let lower = headers.lowercased()
        if lower.contains("transfer-encoding: chunked") { return try dechunk(bytes) }
        if let line = lower.components(separatedBy: "\r\n").first(where: { $0.hasPrefix("content-length:") }),
           let size = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) {
            guard size >= 0, size <= 10_000_000, bytes.count >= size else { throw URLError(.cannotParseResponse) }
            return Data(bytes.prefix(size))
        }
        guard bytes.count <= 10_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        return bytes // close-delimited HTTP/1.1 response
    }

    private static func dechunk(_ body: Data) throws -> Data {
        let bytes = [UInt8](body)
        var position = 0
        var output = Data()
        while position < bytes.count {
            guard let cr = bytes[position...].firstIndex(of: 13),
                  cr + 1 < bytes.count, bytes[cr + 1] == 10 else {
                throw URLError(.cannotParseResponse)
            }
            let line = String(decoding: bytes[position..<cr], as: UTF8.self)
            let prefix = line.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            guard let length = Int(prefix.trimmingCharacters(in: .whitespaces), radix: 16),
                  length >= 0, length <= 10_000_000 else { throw URLError(.cannotParseResponse) }
            position = cr + 2
            if length == 0 { return output } // trailers are not needed for JSON
            guard position + length + 2 <= bytes.count,
                  output.count + length <= 10_000_000,
                  bytes[position + length] == 13, bytes[position + length + 1] == 10 else {
                throw URLError(.cannotParseResponse)
            }
            output.append(contentsOf: bytes[position..<(position + length)])
            position += length + 2
        }
        throw URLError(.cannotParseResponse)
    }
}

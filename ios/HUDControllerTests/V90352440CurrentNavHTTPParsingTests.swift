import Foundation
import XCTest
@testable import HUDController

/// Network framing regression for the optional cellular-only HTTPS path.
/// Does not make live network requests in Xcode CI.
final class V90352440CurrentNavHTTPParsingTests: XCTestCase {
    func testContentLengthResponse() throws {
        let wire = Data("HTTP/1.1 200 OK\r\nContent-Length: 7\r\n\r\n{\"x\":1}".utf8)
        let decoded = try CurrentNavHTTPResponseParser.body(from: wire)
        XCTAssertEqual(String(decoding: decoded, as: UTF8.self), "{\"x\":1}")
    }

    func testChunkedResponse() throws {
        let wire = Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n7\r\n{\"x\":1}\r\n0\r\n\r\n".utf8)
        let decoded = try CurrentNavHTTPResponseParser.body(from: wire)
        XCTAssertEqual(String(decoding: decoded, as: UTF8.self), "{\"x\":1}")
    }

    func testHTTPErrorCannotBeTreatedAsSpeedData() {
        let wire = Data("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 3\r\n\r\nerr".utf8)
        XCTAssertThrowsError(try CurrentNavHTTPResponseParser.body(from: wire))
    }

    func testTruncatedResponseCannotBeUsed() {
        let wire = Data("HTTP/1.1 200 OK\r\nContent-Length: 20\r\n\r\n{}".utf8)
        XCTAssertThrowsError(try CurrentNavHTTPResponseParser.body(from: wire))
    }
}

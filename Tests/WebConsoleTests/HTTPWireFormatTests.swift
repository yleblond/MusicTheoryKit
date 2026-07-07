import XCTest
@testable import WebConsole

final class HTTPWireFormatTests: XCTestCase {
    func testParseRequestLineExtractsMethodAndPath() {
        let request = HTTPWireFormat.parseRequestLine("GET /state HTTP/1.1\r\nHost: localhost\r\n")
        XCTAssertEqual(request?.method, "GET")
        XCTAssertEqual(request?.path, "/state")
    }

    func testParseRequestLineRejectsMalformedLine() {
        // Deliberately lenient (no method whitelist, no HTTP-version check — see its doc
        // comment): the only real guard is "at least a method and a path", so only a line
        // with fewer than two space-separated tokens counts as malformed here.
        XCTAssertNil(HTTPWireFormat.parseRequestLine("GET"))
        XCTAssertNil(HTTPWireFormat.parseRequestLine(""))
    }

    func testResponseHeadIncludesContentLengthAndCloseConnection() {
        let response = HTTPResponse.text("hello", contentType: "text/plain")
        let head = HTTPWireFormat.responseHead(for: response)
        XCTAssertTrue(head.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(head.contains("Content-Type: text/plain\r\n"))
        XCTAssertTrue(head.contains("Content-Length: 5\r\n"))
        XCTAssertTrue(head.contains("Connection: close\r\n"))
        XCTAssertTrue(head.hasSuffix("\r\n\r\n"))
    }

    func testNotFoundResponseIs404() {
        let response = HTTPResponse.notFound()
        XCTAssertEqual(response.status, 404)
    }
}

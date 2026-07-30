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

    func testParseHeadersExtractsMethodPathAndHeaderFields() {
        let parsed = HTTPWireFormat.parseHeaders("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:8765\r\nContent-Type: application/json\r\nContent-Length: 42\r\n")
        XCTAssertEqual(parsed?.method, "POST")
        XCTAssertEqual(parsed?.path, "/mcp")
        XCTAssertEqual(parsed?.headers["Content-Type"], "application/json")
        XCTAssertEqual(parsed?.contentLength, 42)
    }

    func testParseHeadersDefaultsContentLengthToZeroWhenAbsent() {
        let parsed = HTTPWireFormat.parseHeaders("GET /state HTTP/1.1\r\nHost: localhost\r\n")
        XCTAssertEqual(parsed?.contentLength, 0)
    }

    func testParseHeadersContentLengthLookupIsCaseInsensitive() {
        let parsed = HTTPWireFormat.parseHeaders("POST /mcp HTTP/1.1\r\ncontent-length: 7\r\n")
        XCTAssertEqual(parsed?.contentLength, 7)
    }

    func testParseHeadersRejectsMalformedRequestLine() {
        XCTAssertNil(HTTPWireFormat.parseHeaders("GET"))
        XCTAssertNil(HTTPWireFormat.parseHeaders(""))
    }

    func testResponseHeadIncludesExtraHeaders() {
        let response = HTTPResponse(status: 200, contentType: "application/json", body: Data(), extraHeaders: ["Access-Control-Allow-Origin": "*"])
        let head = HTTPWireFormat.responseHead(for: response)
        XCTAssertTrue(head.contains("Access-Control-Allow-Origin: *\r\n"))
    }

    func testHTTPRequestHeaderLookupIsCaseInsensitive() {
        let request = HTTPRequest(method: "POST", path: "/mcp", headers: ["Content-Type": "application/json"])
        XCTAssertEqual(request.header("content-type"), "application/json")
        XCTAssertNil(request.header("accept"))
    }
}

import Foundation

/// A parsed HTTP/1.1 request. `headers`/`body` default to empty/`nil` and were added later
/// (for the embedded MCP server, see `MCPServer.swift` — MCP's Streamable HTTP transport needs
/// real POST bodies and a couple of headers, unlike WebConsole's own GET-only query-string
/// routes) — every existing call site that only ever read `.method`/`.path` keeps compiling
/// unchanged.
public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data?

    public init(method: String, path: String, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    /// Case-insensitive header lookup — HTTP header names are case-insensitive by spec, and
    /// `HTTPWireFormat.parseHeaders` preserves whatever casing the client actually sent.
    public func header(_ name: String) -> String? {
        let lowercased = name.lowercased()
        return headers.first { $0.key.lowercased() == lowercased }?.value
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var contentType: String
    public var body: Data
    /// Extra response headers beyond `Content-Type`/`Content-Length`/`Connection` (which
    /// `HTTPWireFormat.responseHead` always sets itself) — added for the embedded MCP server's
    /// CORS headers (`Access-Control-Allow-Origin` etc.) and `MCP-Session-Id`/`MCP-Protocol-
    /// Version`; empty by default, so every existing WebConsole response is unaffected.
    public var extraHeaders: [String: String]

    public init(status: Int = 200, contentType: String, body: Data, extraHeaders: [String: String] = [:]) {
        self.status = status
        self.contentType = contentType
        self.body = body
        self.extraHeaders = extraHeaders
    }

    public static func text(_ string: String, contentType: String, status: Int = 200, extraHeaders: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(status: status, contentType: contentType, body: Data(string.utf8), extraHeaders: extraHeaders)
    }

    public static func notFound() -> HTTPResponse {
        .text("Not Found", contentType: "text/plain", status: 404)
    }
}

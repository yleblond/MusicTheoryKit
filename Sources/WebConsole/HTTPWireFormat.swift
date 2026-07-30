import Foundation

/// The pure, socket-free half of HTTP/1.1 framing — parsing a request line and formatting a
/// response head — pulled out of `HTTPConnection` specifically so it's testable without a
/// real `NWConnection` (this machine has no `XCTest`; see `SanityChecks`'s mirror of these
/// same cases).
enum HTTPWireFormat {
    /// The byte sequence that ends an HTTP header block — `HTTPConnection` buffers incoming
    /// bytes until this appears before attempting to parse anything.
    static let headerTerminator = Data("\r\n\r\n".utf8)

    /// Parses `"GET /path HTTP/1.1"` (the first line of the header block) into an
    /// `HTTPRequest` — `nil` for anything that isn't at least a method and a path (this
    /// server never needs the HTTP version or any header). Kept exactly as before (still used
    /// by `HTTPWireFormatTests`) — `parseHeaders` below is the superset added for POST/MCP
    /// support, parsing the request line AND every header field.
    static func parseRequestLine(_ headerBlock: String) -> HTTPRequest? {
        let requestLine = headerBlock.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: true).first ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return HTTPRequest(method: String(parts[0]), path: String(parts[1]))
    }

    /// A header block parsed in full — request line plus every `Name: value` header field
    /// (case preserved, last one wins on a duplicate name) — and the `Content-Length` extracted
    /// from them, so `HTTPConnection` knows how many more bytes to wait for before the request
    /// is actually complete (needed for POST bodies, which `parseRequestLine`'s original
    /// GET-only contract never had to consider).
    struct ParsedHeaders {
        let method: String
        let path: String
        let headers: [String: String]
        let contentLength: Int
    }

    static func parseHeaders(_ headerBlock: String) -> ParsedHeaders? {
        let lines = headerBlock.split(separator: "\r\n", omittingEmptySubsequences: true)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        let contentLength = headers.first { $0.key.caseInsensitiveCompare("Content-Length") == .orderedSame }
            .flatMap { Int($0.value) } ?? 0
        return ParsedHeaders(method: String(parts[0]), path: String(parts[1]), headers: headers, contentLength: contentLength)
    }

    /// The status-line + headers to send ahead of `response.body` — always `Connection:
    /// close` (no keep-alive, see `HTTPConnection`) and a `Content-Length` computed from the
    /// body that's about to follow, so the client never has to guess where the response ends.
    static func responseHead(for response: HTTPResponse) -> String {
        var head = "HTTP/1.1 \(response.status) \(statusText(response.status))\r\n"
        head += "Content-Type: \(response.contentType)\r\n"
        head += "Content-Length: \(response.body.count)\r\n"
        for (name, value) in response.extraHeaders {
            head += "\(name): \(value)\r\n"
        }
        head += "Connection: close\r\n\r\n"
        return head
    }

    static func statusText(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        default: return "Error"
        }
    }
}

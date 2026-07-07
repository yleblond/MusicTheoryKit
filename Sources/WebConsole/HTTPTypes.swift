import Foundation

/// A parsed HTTP/1.1 request line — GET-only, no headers/body kept, since every route this
/// server exposes only ever needs the path (see `HTTPServer`'s `onRequest` handler).
public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var contentType: String
    public var body: Data

    public init(status: Int = 200, contentType: String, body: Data) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }

    public static func text(_ string: String, contentType: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, contentType: contentType, body: Data(string.utf8))
    }

    public static func notFound() -> HTTPResponse {
        .text("Not Found", contentType: "text/plain", status: 404)
    }
}

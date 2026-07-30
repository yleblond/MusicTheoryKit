import Foundation
import Network

/// Reads one HTTP/1.1 request off a fresh `NWConnection`, hands it to `handler`, writes back
/// the response, then closes — no keep-alive. Mirrors `NetEngine/FramedConnection.swift`'s
/// shape (accumulate into a buffer, drain once a full unit is available) but looks for the
/// blank line that ends HTTP headers (`\r\n\r\n`) instead of a length-prefixed frame; once the
/// headers are in, a `Content-Length` body (needed for the embedded MCP server's POST
/// requests — see `MCPServer.swift` — WebConsole's own GET routes never send one) is waited
/// for the same way, by re-checking the buffer's size on every subsequent `receiveNext` call.
// `@unchecked Sendable`: `receiveBuffer`/`closed` are only ever touched from the queue this
// connection was started on, same reasoning as `FramedConnection`.
final class HTTPConnection: @unchecked Sendable {
    typealias RequestHandler = (HTTPRequest) -> HTTPResponse

    private let connection: NWConnection
    private var receiveBuffer = Data()
    private let handler: RequestHandler
    private var onClose: (() -> Void)?
    private var closed = false

    init(connection: NWConnection, handler: @escaping RequestHandler) {
        self.connection = connection
        self.handler = handler
    }

    /// `onClose` is this connection's only strong reference once `start` returns (it's
    /// created as a local in `HTTPServer`'s `newConnectionHandler` and never stored anywhere
    /// else) — every callback below captures `self` strongly, so the connection keeps itself
    /// alive for exactly as long as `NWConnection` still has a pending state/receive callback
    /// to deliver, and `onClose` (called from `closeOnce()`) is `HTTPServer`'s cue to drop
    /// its own bookkeeping entry. Weak-self here would let ARC free this object the instant
    /// the accepting closure returns, silently dropping every inbound request — the actual
    /// bug this comment is here to prevent from being reintroduced.
    func start(queue: DispatchQueue, onClose: @escaping () -> Void) {
        self.onClose = onClose
        connection.stateUpdateHandler = { state in
            if case .failed = state { self.closeOnce() }
            if case .cancelled = state { self.closeOnce() }
        }
        connection.start(queue: queue)
        receiveNext()
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                if self.handleRequestIfComplete() { return } // already responded + closing
            }
            if isComplete || error != nil {
                self.closeOnce()
                return
            }
            self.receiveNext()
        }
    }

    /// Once the blank line ending the headers has arrived, parses the request line + headers,
    /// then — if `Content-Length` says a body is coming — waits for that many more bytes to
    /// actually accumulate before calling `handler` (returns `false` meaning "keep receiving,
    /// not done yet"; a plain GET with no body is complete the instant the header terminator
    /// itself arrives, same as before this method grew POST support). Returns `true` once a
    /// response has actually been sent, so `receiveNext` knows to stop reading.
    private func handleRequestIfComplete() -> Bool {
        guard let headerEnd = receiveBuffer.range(of: HTTPWireFormat.headerTerminator) else { return false }
        let headerData = receiveBuffer.subdata(in: receiveBuffer.startIndex..<headerEnd.lowerBound)
        let headerText = String(data: headerData, encoding: .utf8) ?? ""
        guard let parsed = HTTPWireFormat.parseHeaders(headerText) else {
            send(.text("Bad Request", contentType: "text/plain", status: 400))
            return true
        }
        let bodyStart = headerEnd.upperBound
        guard receiveBuffer.distance(from: bodyStart, to: receiveBuffer.endIndex) >= parsed.contentLength else {
            return false // body not fully arrived yet — keep receiving
        }
        let body: Data? = parsed.contentLength > 0
            ? receiveBuffer.subdata(in: bodyStart..<receiveBuffer.index(bodyStart, offsetBy: parsed.contentLength))
            : nil
        let request = HTTPRequest(method: parsed.method, path: parsed.path, headers: parsed.headers, body: body)
        send(handler(request))
        return true
    }

    private func send(_ response: HTTPResponse) {
        var payload = Data(HTTPWireFormat.responseHead(for: response).utf8)
        payload.append(response.body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            self.connection.cancel()
        })
    }

    private func closeOnce() {
        guard !closed else { return }
        closed = true
        onClose?()
        onClose = nil
    }
}

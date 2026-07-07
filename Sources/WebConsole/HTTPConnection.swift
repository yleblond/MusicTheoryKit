import Foundation
import Network

/// Reads one HTTP/1.1 request off a fresh `NWConnection`, hands it to `handler`, writes back
/// the response, then closes — no keep-alive, no request body (this server only ever serves
/// GET routes with no payload), and no header parsing beyond the request line (the one thing
/// every route actually needs is the path). Mirrors `NetEngine/FramedConnection.swift`'s
/// shape (accumulate into a buffer, drain once a full unit is available) but looks for the
/// blank line that ends HTTP headers (`\r\n\r\n`) instead of a length-prefixed frame.
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

    /// Once the blank line ending the headers has arrived, the request line is all this
    /// server needs — parses it, calls `handler`, writes the response, and tears down the
    /// connection (no keep-alive). Returns `true` once a response has been sent (so
    /// `receiveNext` knows not to keep reading), `false` while still waiting for more bytes.
    private func handleRequestIfComplete() -> Bool {
        guard let headerEnd = receiveBuffer.range(of: HTTPWireFormat.headerTerminator) else { return false }
        let headerData = receiveBuffer.subdata(in: receiveBuffer.startIndex..<headerEnd.lowerBound)
        let headerText = String(data: headerData, encoding: .utf8) ?? ""
        let response: HTTPResponse
        if let request = HTTPWireFormat.parseRequestLine(headerText) {
            response = handler(request)
        } else {
            response = .text("Bad Request", contentType: "text/plain", status: 400)
        }
        send(response)
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

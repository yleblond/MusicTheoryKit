import Foundation
import Network

public enum HTTPServerError: Error, CustomStringConvertible {
    case invalidPort

    public var description: String { "invalid port number" }
}

/// A minimal hand-rolled HTTP/1.1 server on top of `Network.framework` — no third-party HTTP
/// stack, matching `NetEngine`'s existing "raw `Network.framework` + a hand-written protocol"
/// style. Every accepted connection is handed to a fresh `HTTPConnection`, which reads exactly
/// one request, answers via `onRequest`, and closes.
// `@unchecked Sendable`: `listener`/`activeConnections` are only ever touched from `queue`
// (every call site below hops onto it), same reasoning as `NetworkServer`.
public final class HTTPServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "HTTPServer")
    private let onRequest: HTTPConnection.RequestHandler
    /// Keyed by identity rather than a generated id (unlike `NetworkServer.connections`,
    /// nothing outside this class ever needs to address one by id) — its only job is to hold
    /// a strong reference for exactly as long as each one-shot `HTTPConnection` is in flight,
    /// removed via its `onClose` callback once it has responded and torn itself down. Without
    /// this, a connection created as a local in `newConnectionHandler` and never stored
    /// anywhere would be deallocated the instant that closure returns — see `HTTPConnection`'s
    /// own doc comment on `start` for the bug this specifically fixes.
    private var activeConnections: [ObjectIdentifier: HTTPConnection] = [:]

    public init(onRequest: @escaping (HTTPRequest) -> HTTPResponse) {
        self.onRequest = onRequest
    }

    public func start(port: UInt16) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw HTTPServerError.invalidPort }
        let newListener = try NWListener(using: .tcp, on: nwPort)
        newListener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            let httpConnection = HTTPConnection(connection: connection, handler: self.onRequest)
            let key = ObjectIdentifier(httpConnection)
            self.activeConnections[key] = httpConnection
            // Strong `self` here is intentional and short-lived, not a leak: this closure is
            // itself only reachable through `activeConnections[key]` (i.e. through `self`),
            // and `onClose` fires exactly once per connection, milliseconds after it's
            // created (one request, one response, done) — clearing this entry (and thus this
            // closure) right after. A `weak self` two closures deep here just fights the
            // Swift 6 concurrency checker for no real benefit.
            httpConnection.start(queue: self.queue) {
                self.activeConnections.removeValue(forKey: key)
            }
        }
        newListener.start(queue: queue)
        listener = newListener
    }

    /// Strong `self` (not `[weak self]`) is required here: a caller typically does
    /// `webConsoleServer?.stop(); webConsoleServer = nil` back to back (see
    /// `ImprovSession.stopWebConsole()`), dropping its only strong reference to this instance
    /// right after calling `stop()` — before this `queue.async` block has actually run. With
    /// a weak capture, `self` would already be `nil` by the time it executes, `cancel()`
    /// would never actually fire, and the underlying `NWListener` — which `Network.framework`
    /// keeps alive internally once started, independent of our own reference — would keep
    /// listening forever (confirmed with `lsof`: the port stayed in `LISTEN` well past when
    /// this returned). Capturing `self` strongly keeps this instance alive just long enough
    /// for its own cleanup to run, mirroring `HTTPConnection.send`'s reasoning for the same fix.
    public func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            self.activeConnections.removeAll()
        }
    }
}

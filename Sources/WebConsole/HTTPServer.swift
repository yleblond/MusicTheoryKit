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

    /// `host`, when provided, restricts the listener to that one local address (e.g.
    /// `"127.0.0.1"` for loopback-only — used by the embedded MCP server, see `MCPServer.swift`,
    /// since its tools allow far more powerful control of the app than WebConsole's own browser
    /// UI, with no authentication at all) via `NWParameters.requiredLocalEndpoint`. `nil` (the
    /// default) preserves the original behavior: bind every LOCAL-NETWORK interface, as
    /// WebConsole/virtual keyboard still do (their own LAN-reachability — another device's
    /// browser/phone needs to reach them — is intentional, see their own doc comments; loopback-
    /// only here would silently break that). Either way, `prohibitedInterfaceTypes = [.cellular]`
    /// always applies (BACKLOG.md's "revérifier le binding réseau" entry, 2026-08-16): a listener
    /// bound to "all interfaces" still includes whatever route mobile data provides (e.g.
    /// Personal Hotspot sharing), which is never a same-room LAN device — excluding it costs
    /// nothing for the legitimate Wi-Fi/Ethernet LAN use case. Deliberately NOT a fix for the
    /// "untrusted shared Wi-Fi" (café/conference) scenario the backlog entry actually named —
    /// Network.framework has no notion of "trusted vs untrusted Wi-Fi," anyone else on the same
    /// Wi-Fi network can still reach these unauthenticated/unencrypted servers exactly as before;
    /// that gap needs actual auth, tracked separately, not an interface-type filter.
    public func start(port: UInt16, host: String? = nil) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw HTTPServerError.invalidPort }
        let newListener: NWListener
        if let host {
            // `requiredLocalEndpoint` already fully specifies host AND port — passing `on:`
            // as well (i.e. `NWListener(using:on:)`) makes the two port specifications
            // conflict, which `NWListener` rejects outright (confirmed: threw POSIX EINVAL
            // "Invalid argument" at `.start(queue:)` when both were set).
            let parameters: NWParameters = .tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
            parameters.prohibitedInterfaceTypes = [.cellular]
            newListener = try NWListener(using: parameters)
        } else {
            let parameters: NWParameters = .tcp
            parameters.prohibitedInterfaceTypes = [.cellular]
            newListener = try NWListener(using: parameters, on: nwPort)
        }
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

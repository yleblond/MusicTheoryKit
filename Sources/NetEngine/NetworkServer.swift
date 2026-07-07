import Foundation
import Network

/// Accepts any number of simultaneous client connections on one TCP port and relays
/// `NetMessage`s to/from a single handler — deliberately promiscuous (any client that can
/// reach the port is accepted, no auth/allow-list), matching this first version's "purely
/// collaborative, no gatekeeping" design. Every public method hops onto `queue` so
/// `connections` is only ever touched from one thread, the same discipline `AppCore`
/// already applies to its own shared mutable state.
// `@unchecked Sendable`: `connections`/`listener` are only ever mutated from `queue` (every
// public method that touches them hops onto it via `.async`), same reasoning as
// `ImprovSession`'s own `@unchecked Sendable`.
public final class NetworkServer: @unchecked Sendable {
    /// `connectionID` is a per-TCP-connection identifier assigned here, not the
    /// participant's own persistent `clientID` from its `hello` message (that arrives only
    /// after the connection is already up, and one participant could in principle reconnect
    /// under a fresh connection) — callers that need the participant identity read it out
    /// of the `hello`/`trackAnnounce` messages themselves.
    public typealias MessageHandler = (String, NetMessage) -> Void
    public typealias DisconnectHandler = (String) -> Void

    private var listener: NWListener?
    private var connections: [String: FramedConnection] = [:]
    private let queue = DispatchQueue(label: "NetworkServer")
    private let onMessage: MessageHandler
    private let onDisconnect: DisconnectHandler

    public init(onMessage: @escaping MessageHandler, onDisconnect: @escaping DisconnectHandler) {
        self.onMessage = onMessage
        self.onDisconnect = onDisconnect
    }

    /// `advertisedAs`, when given, makes this server discoverable on the local network via
    /// Bonjour/mDNS under that display name (see `ServiceBrowser.discover`) — `nil` starts
    /// a listener that only accepts connections to a known host/port, same as before this
    /// existed.
    public func start(port: UInt16, advertisedAs serviceName: String? = nil) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw NetworkError.invalidPort }
        let newListener = try NWListener(using: .tcp, on: nwPort)
        if let serviceName {
            newListener.service = NWListener.Service(name: serviceName, type: ServiceBrowser.serviceType)
        }
        newListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        newListener.start(queue: queue)
        listener = newListener
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            for connection in self.connections.values { connection.cancel() }
            self.connections.removeAll()
        }
    }

    public func send(_ message: NetMessage, to connectionID: String) {
        queue.async { [weak self] in
            self?.connections[connectionID]?.send(message)
        }
    }

    public func broadcast(_ message: NetMessage) {
        queue.async { [weak self] in
            guard let self else { return }
            for connection in self.connections.values { connection.send(message) }
        }
    }

    private func accept(_ connection: NWConnection) {
        let connectionID = UUID().uuidString
        let framed = FramedConnection(
            connection: connection,
            handler: { [weak self] message in self?.onMessage(connectionID, message) },
            onClose: { [weak self] in self?.remove(connectionID) }
        )
        connections[connectionID] = framed
        framed.start(queue: queue)
    }

    private func remove(_ connectionID: String) {
        queue.async { [weak self] in
            self?.connections.removeValue(forKey: connectionID)
        }
        onDisconnect(connectionID)
    }
}

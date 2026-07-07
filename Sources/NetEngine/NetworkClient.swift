import Foundation
import Network

/// A single outbound connection to a `NetworkServer` — connects, then relays
/// `NetMessage`s to/from a handler for as long as the connection stays up. `sendOnReady`
/// (typically a `hello` followed by an announce per already-listening local track) is
/// queued until the connection actually reaches `.ready`, rather than risking it being sent
/// (and dropped) mid-handshake.
// `@unchecked Sendable`: `framed` is only ever touched from `queue` — every public method
// hops onto it via `.async`/`.sync`, and `FramedConnection`'s own callbacks already run
// there too (it was `start(queue:)`-ed with this same queue) — same reasoning as
// `ImprovSession`'s own `@unchecked Sendable`.
public final class NetworkClient: @unchecked Sendable {
    public typealias MessageHandler = (NetMessage) -> Void
    public typealias DisconnectHandler = () -> Void

    private var framed: FramedConnection?
    private let queue = DispatchQueue(label: "NetworkClient")
    private let onMessage: MessageHandler
    private let onDisconnect: DisconnectHandler

    public init(onMessage: @escaping MessageHandler, onDisconnect: @escaping DisconnectHandler) {
        self.onMessage = onMessage
        self.onDisconnect = onDisconnect
    }

    public func connect(host: String, port: UInt16, sendOnReady messages: [NetMessage]) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw NetworkError.invalidPort }
        connect(to: NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp), sendOnReady: messages)
    }

    /// Connects to a server found via `ServiceBrowser.discover` — `endpoint` is opaque
    /// (a Bonjour `.service` endpoint); Network.framework resolves it to an actual
    /// host/port itself, there's nothing for this call to validate up front the way the
    /// host/port overload above does.
    public func connect(to endpoint: NWEndpoint, sendOnReady messages: [NetMessage]) {
        connect(to: NWConnection(to: endpoint, using: .tcp), sendOnReady: messages)
    }

    private func connect(to connection: NWConnection, sendOnReady messages: [NetMessage]) {
        let newFramed = FramedConnection(
            connection: connection,
            handler: { [weak self] received in self?.onMessage(received) },
            onClose: { [weak self] in self?.disconnect(notifying: true) }
        )
        queue.sync { framed = newFramed }
        newFramed.start(queue: queue) { [weak newFramed] in
            for message in messages { newFramed?.send(message) }
        }
    }

    public func send(_ message: NetMessage) {
        queue.async { [weak self] in
            self?.framed?.send(message)
        }
    }

    public func disconnect() {
        disconnect(notifying: false)
    }

    private func disconnect(notifying: Bool) {
        queue.async { [weak self] in
            self?.framed?.cancel()
            self?.framed = nil
            if notifying { self?.onDisconnect() }
        }
    }
}

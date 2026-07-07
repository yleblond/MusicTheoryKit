import Foundation
import Network

public enum NetworkError: Error, CustomStringConvertible {
    case invalidPort
    case connectionFailed

    public var description: String {
        switch self {
        case .invalidPort: return "invalid port number"
        case .connectionFailed: return "could not connect to the server"
        }
    }
}

/// Sends/receives `NetMessage` values over a persistent `NWConnection`, each one framed as
/// a 4-byte big-endian length prefix followed by its JSON encoding — simple enough to hand-
/// write correctly (no HTTP, no WebSocket handshake/framing) while still being unambiguous
/// about where one message ends and the next begins, unlike newline-delimited JSON (a
/// message's own content could in principle contain a literal newline).
// `@unchecked Sendable`: every mutable property (`receiveBuffer`, `onReady`, `closed`) is
// only ever touched from the single `DispatchQueue` this connection was started on — all of
// `NWConnection`'s own callbacks (`stateUpdateHandler`, `receive`) run there by construction
// (`start(queue:)`), same reasoning as `ImprovSession`'s own `@unchecked Sendable`.
public final class FramedConnection: @unchecked Sendable {
    public typealias MessageHandler = (NetMessage) -> Void
    public typealias CloseHandler = () -> Void
    public typealias ReadyHandler = () -> Void

    private let connection: NWConnection
    private var receiveBuffer = Data()
    private let handler: MessageHandler
    private let onClose: CloseHandler
    private var onReady: ReadyHandler?
    private var closed = false

    public init(connection: NWConnection, handler: @escaping MessageHandler, onClose: @escaping CloseHandler) {
        self.connection = connection
        self.handler = handler
        self.onClose = onClose
    }

    /// `onReady` fires once, the first time the connection reaches `.ready` — sending
    /// before that point risks the bytes being silently dropped by the not-yet-established
    /// TCP handshake, so callers that need a "connected" signal (e.g. to send `hello`)
    /// should wait for this rather than sending immediately after `start(queue:)` returns.
    public func start(queue: DispatchQueue, onReady: ReadyHandler? = nil) {
        self.onReady = onReady
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onReady?()
                self?.onReady = nil
            case .failed, .cancelled:
                self?.closeOnce()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveNext()
    }

    public func cancel() {
        connection.cancel()
    }

    public func send(_ message: NetMessage) {
        guard let payload = try? JSONEncoder().encode(message) else { return }
        var frame = Data()
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.drainCompleteFrames()
            }
            if isComplete || error != nil {
                self.closeOnce()
                return
            }
            self.receiveNext()
        }
    }

    private func drainCompleteFrames() {
        while receiveBuffer.count >= 4 {
            let length = receiveBuffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let total = 4 + Int(length)
            guard receiveBuffer.count >= total else { return }
            let payload = receiveBuffer.subdata(in: 4..<total)
            receiveBuffer.removeSubrange(0..<total)
            if let message = try? JSONDecoder().decode(NetMessage.self, from: payload) {
                handler(message)
            }
        }
    }

    private func closeOnce() {
        guard !closed else { return }
        closed = true
        onClose()
    }
}

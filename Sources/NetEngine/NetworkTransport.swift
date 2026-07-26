/// The server-shaped half of the collaborative-session wire protocol: address one
/// participant by its connection identity, or every participant at once. `NetworkServer`
/// already has exactly this method shape (see its own file) — this protocol exists so
/// `ImprovSession` can hold EITHER it or `GameCenterTransport` (acting as organizer) behind
/// one type, and reuse the same server-side message-handling code for both.
public protocol NetworkServerTransport: AnyObject {
    func send(_ message: NetMessage, to connectionID: String)
    func broadcast(_ message: NetMessage)
    func stop()
}

/// The client-shaped half of the collaborative-session wire protocol: exactly one
/// destination (the server/organizer), so a plain send with no recipient. `NetworkClient`
/// already has exactly this method shape — see `NetworkServerTransport`'s own doc comment for
/// why this exists as a protocol.
public protocol NetworkClientTransport: AnyObject {
    func send(_ message: NetMessage)
    func disconnect()
}

extension NetworkServer: NetworkServerTransport {}
extension NetworkClient: NetworkClientTransport {}

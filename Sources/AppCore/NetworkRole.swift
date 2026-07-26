/// Which side of a collaborative session (if any) this `ImprovSession` is currently
/// playing — see `ImprovSession.startServer`/`connectToServer` (local network) and
/// `startGameCenterServer`/`joinGameCenterSession` (internet, via Game Center matchmaking).
/// Mutually exclusive: only one role can be active at a time in this first version.
public enum NetworkRole: Sendable, Equatable {
    case standalone
    case server(port: Int)
    /// `description` is a display string only ("host:port" for a manually-entered address,
    /// or the discovered server's advertised name for `connectToServer(discovered:)`) — a
    /// Bonjour connection never resolves to a host/port a caller is meant to read back out.
    case client(description: String)
    /// Hosting a session over Game Center's matchmaking instead of a local TCP listener —
    /// no port to display (Game Center owns the actual connection details).
    case gameCenterServer
    /// `description` mirrors `.client`'s own — the organizer's display name, not a
    /// host/port (there isn't one to show for a Game Center connection).
    case gameCenterClient(description: String)

    /// True for either server-shaped role (`.server`/`.gameCenterServer`) — lets
    /// `ImprovSession`'s server-side logic (stop, broadcast, ...) treat both transports
    /// uniformly instead of duplicating every call site's `switch`.
    public var isServerRole: Bool {
        switch self {
        case .server, .gameCenterServer: return true
        case .standalone, .client, .gameCenterClient: return false
        }
    }

    /// True for either client-shaped role (`.client`/`.gameCenterClient`) — see
    /// `isServerRole`'s own doc comment for why this exists.
    public var isClientRole: Bool {
        switch self {
        case .client, .gameCenterClient: return true
        case .standalone, .server, .gameCenterServer: return false
        }
    }
}

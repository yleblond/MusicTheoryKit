/// Which side of a collaborative session (if any) this `ImprovSession` is currently
/// playing — see `ImprovSession.startServer`/`connectToServer`. Mutually exclusive: only
/// one role can be active at a time in this first version.
public enum NetworkRole: Sendable, Equatable {
    case standalone
    case server(port: Int)
    /// `description` is a display string only ("host:port" for a manually-entered address,
    /// or the discovered server's advertised name for `connectToServer(discovered:)`) — a
    /// Bonjour connection never resolves to a host/port a caller is meant to read back out.
    case client(description: String)
}

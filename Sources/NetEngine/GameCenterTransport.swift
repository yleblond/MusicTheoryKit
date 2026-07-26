import Foundation
import GameKit

/// A `GKMatch`-backed analog of `NetworkServer`/`NetworkClient`: same `NetMessage`
/// send/receive shape (see `NetworkServerTransport`/`NetworkClientTransport`), but running
/// over Game Center's own matchmaking connection (works over the internet, NAT traversal and
/// relay handled by Apple) instead of a local-network TCP listener.
///
/// **Unlike `NetworkServer`/`NetworkClient`, a `GKMatch` itself has no server/client
/// asymmetry** — every matched player can send to every other directly. This app's own
/// "organizer broadcasts `sync`, everyone else talks only to the organizer" model is layered
/// on top here, not something GameKit provides:
/// - As `.organizer`, `send(_:to:)`/`broadcast(_:)` address one or all currently-matched
///   players — the same shape `NetworkServer` already has, so `ImprovSession`'s existing
///   server-side message handling (`handleServerMessage`, `broadcastSyncSoon`) works
///   unmodified.
/// - As `.participant`, the no-recipient `send(_:)` targets `match.players.first` — **scoped
///   to exactly one organizer per match in this first version**: with more than 2 matched
///   players, a participant would need to know WHICH other player is the organizer (GKMatch
///   doesn't expose "who hosts" itself), which this doesn't attempt to resolve yet. Fine for
///   the common case this was built for (one organizer + one participant, a duo jam session)
///   — a real limitation to lift later, not a silent gap.
public final class GameCenterTransport: NSObject, @unchecked Sendable {
    /// `String` is the sender's `GKPlayer.gamePlayerID` — the stable per-player-per-game
    /// identifier GameKit recommends over the deprecated `playerID`, used as this
    /// transport's `connectionID` (matching `NetworkServer`'s own per-connection UUID in
    /// spirit: an opaque handle the caller uses to address a specific participant, not
    /// something to parse).
    public typealias MessageHandler = (String, NetMessage) -> Void
    public typealias DisconnectHandler = (String) -> Void

    public enum Role {
        case organizer
        case participant
    }

    private let match: GKMatch
    private let role: Role
    private let onMessage: MessageHandler
    private let onDisconnect: DisconnectHandler

    public init(match: GKMatch, role: Role, onMessage: @escaping MessageHandler, onDisconnect: @escaping DisconnectHandler) {
        self.match = match
        self.role = role
        self.onMessage = onMessage
        self.onDisconnect = onDisconnect
        super.init()
        match.delegate = self
    }

    /// Organizer-shaped send: one specific participant.
    public func send(_ message: NetMessage, to connectionID: String) {
        guard let player = match.players.first(where: { $0.gamePlayerID == connectionID }) else { return }
        guard let data = try? JSONEncoder().encode(message) else { return }
        try? match.send(data, to: [player], dataMode: .reliable)
    }

    /// Organizer-shaped send: every currently-matched participant.
    public func broadcast(_ message: NetMessage) {
        guard !match.players.isEmpty, let data = try? JSONEncoder().encode(message) else { return }
        try? match.sendData(toAllPlayers: data, with: .reliable)
    }

    /// Participant-shaped send: the organizer, implicitly (see this type's own doc comment
    /// for the one-organizer-per-match scope this relies on).
    public func send(_ message: NetMessage) {
        guard let organizer = match.players.first else { return }
        guard let data = try? JSONEncoder().encode(message) else { return }
        try? match.send(data, to: [organizer], dataMode: .reliable)
    }

    public func stop() {
        match.delegate = nil
        match.disconnect()
    }

    public func disconnect() {
        stop()
    }
}

extension GameCenterTransport: GKMatchDelegate {
    public func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        guard let message = try? JSONDecoder().decode(NetMessage.self, from: data) else { return }
        onMessage(player.gamePlayerID, message)
    }

    public func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        guard state == .disconnected else { return }
        onDisconnect(player.gamePlayerID)
    }
}

extension GameCenterTransport: NetworkServerTransport, NetworkClientTransport {}

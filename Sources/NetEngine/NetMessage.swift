import Foundation

/// One wire message of the collaborative-session protocol — a flat, single `Codable`
/// struct (not an enum with associated values) so hand-written JSON encode/decode stays
/// trivial: `kind` says which of the other fields are meaningful, unused fields are `nil`.
public struct NetMessage: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// Client -> server, sent once right after connecting: declares this participant's
        /// persistent identity.
        case hello
        /// Server -> client, acknowledges `hello`. The first real state arrives in the next
        /// `sync` broadcast, not in this message.
        case helloAck
        /// Client -> server: "one of my local tracks just started/updated listening."
        case trackAnnounce
        /// Client -> server: "one of my local tracks just stopped listening."
        case trackUnannounce
        /// Client -> server: a raw note on/off from one of my local tracks.
        case noteEvent
        /// Server -> every client, broadcast periodically and on change: the full merged
        /// track list (the server's own local tracks plus every connected client's
        /// announced tracks), each already carrying its recognized chord/mode/held pitches
        /// — the server is the single source of truth for recognition, clients never
        /// re-derive it themselves.
        case sync
    }

    public var kind: Kind
    public var clientID: String?
    public var clientName: String?
    public var trackID: String?
    public var label: String?
    public var canHaveSound: Bool?
    public var isNoteOn: Bool?
    public var pitch: Int?
    public var velocity: Int?
    public var channel: Int?
    public var tracks: [RemoteTrackSnapshot]?

    public init(
        kind: Kind, clientID: String? = nil, clientName: String? = nil, trackID: String? = nil,
        label: String? = nil, canHaveSound: Bool? = nil, isNoteOn: Bool? = nil, pitch: Int? = nil,
        velocity: Int? = nil, channel: Int? = nil, tracks: [RemoteTrackSnapshot]? = nil
    ) {
        self.kind = kind
        self.clientID = clientID
        self.clientName = clientName
        self.trackID = trackID
        self.label = label
        self.canHaveSound = canHaveSound
        self.isNoteOn = isNoteOn
        self.pitch = pitch
        self.velocity = velocity
        self.channel = channel
        self.tracks = tracks
    }
}

/// One track's full display-relevant state, as broadcast by the server in a `sync`
/// message — a client renders every one of these it doesn't own itself as a read-only
/// remote track.
public struct RemoteTrackSnapshot: Codable, Sendable, Equatable {
    public var clientID: String
    public var trackID: String
    public var label: String
    public var isListening: Bool
    public var canHaveSound: Bool
    public var heldPitches: [Int]
    public var chordName: String?
    public var modesText: String?

    public init(
        clientID: String, trackID: String, label: String, isListening: Bool, canHaveSound: Bool,
        heldPitches: [Int], chordName: String? = nil, modesText: String? = nil
    ) {
        self.clientID = clientID
        self.trackID = trackID
        self.label = label
        self.isListening = isListening
        self.canHaveSound = canHaveSound
        self.heldPitches = heldPitches
        self.chordName = chordName
        self.modesText = modesText
    }
}

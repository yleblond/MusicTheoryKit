import Foundation

/// A best-effort hint of which physical/virtual instrument last occupied a `SceneRole`, used
/// only to decide whether to automatically reattach it on `loadScene` (see
/// `ImprovSession.matches(_:_:)`) — never a hard requirement, since none of these are stable
/// enough to trust blindly (see each case's own comment). Deliberately no `.remote` case yet:
/// this is a local/standalone-only concept for now — extending it later (plus widening the two
/// switches that consume it) is the intended seam for a future collaborative-session round
/// where a network client could claim a role too.
public enum InstrumentIdentityHint: Codable, Equatable, Sendable {
    case midiMerged
    /// `midiUniqueID` is CoreMIDI's own persistent per-device id (`kMIDIPropertyUniqueID`),
    /// stable across unplug/replug on this Mac in the ordinary case — genuinely reliable,
    /// unlike `TrackID.midiSource(Int)`'s own raw enumeration-order index, which this hint
    /// exists specifically to stop relying on for reattachment. `nil` for a hint captured
    /// before this property was adopted, or migrated from an old scene file with no such
    /// history — falls back to `displayName`-based matching in that case (see
    /// `ImprovSession.matches(_:_:)`).
    case midiPort(midiUniqueID: Int32?, displayName: String)
    case computerKeyboard
    /// `clientID` is the browser's own `localStorage`-persisted UUID — stable across a reload
    /// of the SAME browser/device, not a device-independent identity.
    case webKeyboard(clientID: String)
    case microphone
}

/// One musical position ("Piano 1", "Basse Guitare", "Saxophoniste") declared independently
/// of whatever happens to be plugged in right now — the fix for a real, reported problem: the
/// previous `SceneTrack`-only model kept an instrument's config keyed directly on
/// `TrackID.wireIDText`, which for a MIDI port is nothing more than CoreMIDI's own raw
/// enumeration-order index (see `ImprovSession.loadScene`'s doc comment) — unplugging a
/// keyboard, or plugging a second one in first, silently broke reattachment with zero
/// feedback. A `SceneRole` instead owns its own sound (`soundName`) and is only ever ATTACHED
/// to a live instrument at runtime (`attachedTrackID`, deliberately transient — see this
/// type's own `Codable` conformance below) — so "Piano 1" keeps wanting a piano sound
/// regardless of which physical keyboard is playing it this session.
public struct SceneRole: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    /// The ROLE's own instrument sound — applied to whoever attaches to it (see
    /// `ImprovSession.attachInstrument(_:toRole:)`), not tied to any specific device.
    public var soundName: String?
    public var isListening: Bool
    public var soundEnabled: Bool
    /// A best-effort hint of the last-attached instrument's identity, persisted so
    /// `loadScene` can try to reattach the SAME instrument automatically — see
    /// `ImprovSession.matches(_:_:)` for the exact matching rules per hint kind.
    public var lastAttachedInstrument: InstrumentIdentityHint?

    /// TRANSIENT — which live track currently occupies this role, if any. Deliberately never
    /// persisted (see this type's own `Codable` conformance below): it's a snapshot of the
    /// live session, exactly like a track's own `heldPitches`/recognition state already isn't
    /// captured by a saved scene either.
    public var attachedTrackID: TrackID?

    public init(
        id: UUID = UUID(), name: String, soundName: String? = nil, isListening: Bool = false,
        soundEnabled: Bool = false, lastAttachedInstrument: InstrumentIdentityHint? = nil,
        attachedTrackID: TrackID? = nil
    ) {
        self.id = id
        self.name = name
        self.soundName = soundName
        self.isListening = isListening
        self.soundEnabled = soundEnabled
        self.lastAttachedInstrument = lastAttachedInstrument
        self.attachedTrackID = attachedTrackID
    }
}

extension SceneRole: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, soundName, isListening, soundEnabled, lastAttachedInstrument
        // `attachedTrackID` deliberately absent — see this type's own doc comment.
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        soundName = try container.decodeIfPresent(String.self, forKey: .soundName)
        isListening = try container.decode(Bool.self, forKey: .isListening)
        soundEnabled = try container.decode(Bool.self, forKey: .soundEnabled)
        lastAttachedInstrument = try container.decodeIfPresent(InstrumentIdentityHint.self, forKey: .lastAttachedInstrument)
        attachedTrackID = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(soundName, forKey: .soundName)
        try container.encode(isListening, forKey: .isListening)
        try container.encode(soundEnabled, forKey: .soundEnabled)
        try container.encodeIfPresent(lastAttachedInstrument, forKey: .lastAttachedInstrument)
    }
}

extension SceneRole {
    /// Builds a role from an old-format `SceneTrack` (see `Scene`'s own migration
    /// `init(from:)`) — auto-named from the wire id since the old format never had a
    /// human-facing role name, with `midiUniqueID: nil` (no CoreMIDI identity history to draw
    /// on from the old format, see `InstrumentIdentityHint.midiPort`'s own doc comment) so it
    /// won't cleanly auto-reattach on the very first load after migration — accepted,
    /// one-time cost; the very next save captures a proper hint via
    /// `ImprovSession.identityHint(for:)`.
    public init(migratedFrom sceneTrack: SceneTrack) {
        let hint: InstrumentIdentityHint?
        let migratedName: String
        switch TrackID(wireIDText: sceneTrack.trackID) {
        case .midiMerged:
            hint = .midiMerged
            migratedName = "MIDI (fusionne)"
        case .midiSource(let index):
            hint = .midiPort(midiUniqueID: nil, displayName: "MIDI port \(index + 1)")
            migratedName = "MIDI port \(index + 1)"
        case .computerKeyboard:
            hint = .computerKeyboard
            migratedName = "Clavier ordinateur"
        case .webKeyboard(let clientID):
            hint = .webKeyboard(clientID: clientID)
            migratedName = "Clavier web"
        case .microphone:
            hint = .microphone
            migratedName = "Microphone"
        case .remote, .none:
            hint = nil
            migratedName = sceneTrack.trackID
        }
        self.init(
            name: migratedName, soundName: sceneTrack.instrumentName, isListening: sceneTrack.isListening,
            soundEnabled: sceneTrack.soundEnabled, lastAttachedInstrument: hint
        )
    }
}

/// One track's saved instrument configuration within a `Scene` — LEGACY, decode-only. Kept so
/// `Scene.init(from:)` can still read a scene file saved before the `SceneRole` redesign (see
/// `SceneRole.init(migratedFrom:)`); never written by `saveScene` anymore.
public struct SceneTrack: Codable, Equatable, Sendable {
    public var trackID: String
    public var isListening: Bool
    public var soundEnabled: Bool
    public var instrumentName: String?

    public init(trackID: String, isListening: Bool, soundEnabled: Bool, instrumentName: String?) {
        self.trackID = trackID
        self.isListening = isListening
        self.soundEnabled = soundEnabled
        self.instrumentName = instrumentName
    }
}

/// A saved snapshot of a scene's declared musical positions (`SceneRole`s) — never which live
/// instrument occupies each one (see `SceneRole.attachedTrackID`'s own doc comment) — captured
/// via `ImprovSession.saveScene`, restored via `ImprovSession.loadScene`.
public struct Scene: Equatable, Sendable {
    public var title: String
    public var roles: [SceneRole]

    public init(title: String, roles: [SceneRole] = []) {
        self.title = title
        self.roles = roles
    }
}

extension Scene: Codable {
    private enum CodingKeys: String, CodingKey {
        case title, roles
    }
    /// The on-disk shape of every scene file saved before this redesign:
    /// `{"title": ..., "tracks": [SceneTrack]}`.
    private enum LegacyCodingKeys: String, CodingKey {
        case title, tracks
    }

    /// Accepts the current format (`roles`) as well as every scene file saved before this
    /// redesign (`tracks`, decoded as `[SceneTrack]` then migrated via
    /// `SceneRole.init(migratedFrom:)`) — same "decode the current shape, fall back to the old
    /// one" convention already used by `GuideStep.init(from:)`
    /// (`Sources/PieceModel/GuideSequence.swift`) for its own, analogous format change.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        if container.contains(.roles) {
            roles = try container.decode([SceneRole].self, forKey: .roles)
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            let tracks = try legacy.decodeIfPresent([SceneTrack].self, forKey: .tracks) ?? []
            roles = tracks.map(SceneRole.init(migratedFrom:))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(roles, forKey: .roles)
    }
}

import MusicTheoryKit

/// A user-authored ordered list of mode "steps" to navigate live (see
/// `ImprovSession.startGuide`/`advanceGuideStep`) — deliberately NOT a `Piece`: a guide step
/// is only "which mode are we in" (plus, optionally, a chord progression attached to that
/// mode — see `GuideStep`), with no tempo, tracks, or timing.
public struct GuideSequence: Codable, Equatable, Sendable {
    public var title: String
    public var steps: [GuideStep]

    public init(title: String, steps: [GuideStep] = []) {
        self.title = title
        self.steps = steps
    }
}

/// One step of a `GuideSequence` — a mode to navigate to, optionally paired with a chord
/// progression resolved against that mode at the moment it was added (see
/// `ImprovSession.resolveChordProgression`/`AppCore.ChordProgressionTemplate`) — this is what
/// turns a step from "just a mode" into almost a mini-piece (mode + chord sequence, still
/// missing only melodic lines). `chordProgression` is stored already-resolved, not
/// recomputed from `chordProgressionName` on load — the template library it was chosen from
/// could change or disappear later without invalidating a guide file that already has one.
public struct GuideStep: Codable, Equatable, Sendable {
    public var mode: ModeReference
    /// The template's own name at the time it was chosen — for display/re-editing, not
    /// re-resolved from it (see this type's own doc comment).
    public var chordProgressionName: String?
    public var chordProgression: [ChordReference]?

    public init(mode: ModeReference, chordProgressionName: String? = nil, chordProgression: [ChordReference]? = nil) {
        self.mode = mode
        self.chordProgressionName = chordProgressionName
        self.chordProgression = chordProgression
    }

    private enum CodingKeys: String, CodingKey {
        case mode, chordProgressionName, chordProgression
    }

    /// Accepts the current format (`{"mode": {...}, "chordProgressionName": ..., ...}`) as
    /// well as the format every guide file saved before chord progressions existed: the
    /// object itself IS a bare `ModeReference` (`{"tonic": ..., "scaleID": ...}`, no "mode"
    /// key) — same "decodeIfPresent + fallback" convention as `ColorPalette.textColors`.
    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let mode = try? container.decode(ModeReference.self, forKey: .mode) {
            self.mode = mode
            chordProgressionName = try? container.decodeIfPresent(String.self, forKey: .chordProgressionName)
            chordProgression = try? container.decodeIfPresent([ChordReference].self, forKey: .chordProgression)
        } else {
            mode = try ModeReference(from: decoder)
            chordProgressionName = nil
            chordProgression = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(chordProgressionName, forKey: .chordProgressionName)
        try container.encodeIfPresent(chordProgression, forKey: .chordProgression)
    }
}

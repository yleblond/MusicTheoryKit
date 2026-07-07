import Foundation

/// A structural block of a piece (Intro, Verse, Chorus...): a shared harmonic context
/// (mode, optional transition, chord progression) plus one or more instrument tracks.
public struct Section: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var lengthInMeasures: Int
    public var mode: ModeReference
    public var modeTransition: ModeTransition?
    public var chordProgression: [ChordEvent]
    public var tracks: [Track]
    /// Sample file name (matched against a sample folder, e.g. "mcb.sf2") for this
    /// section's chord progression specifically — separate from any track's own
    /// `instrument`, since chords have no track of their own. `nil` (the default, and what
    /// every pre-existing piece file decodes to, since the key is simply absent) means "use
    /// the piece-playback default sound," exactly like today.
    public var chordInstrument: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        lengthInMeasures: Int,
        mode: ModeReference,
        modeTransition: ModeTransition? = nil,
        chordProgression: [ChordEvent] = [],
        tracks: [Track] = [],
        chordInstrument: String? = nil
    ) {
        self.id = id
        self.name = name
        self.lengthInMeasures = lengthInMeasures
        self.mode = mode
        self.modeTransition = modeTransition
        self.chordProgression = chordProgression
        self.tracks = tracks
        self.chordInstrument = chordInstrument
    }
}

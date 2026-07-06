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

    public init(
        id: String = UUID().uuidString,
        name: String,
        lengthInMeasures: Int,
        mode: ModeReference,
        modeTransition: ModeTransition? = nil,
        chordProgression: [ChordEvent] = [],
        tracks: [Track] = []
    ) {
        self.id = id
        self.name = name
        self.lengthInMeasures = lengthInMeasures
        self.mode = mode
        self.modeTransition = modeTransition
        self.chordProgression = chordProgression
        self.tracks = tracks
    }
}

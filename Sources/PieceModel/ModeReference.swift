import MusicTheoryKit

/// A lightweight, Codable pointer to a `Mode` from MusicTheoryKit's `ScaleLibrary`.
/// Kept separate from `Mode` itself so the piece model stays plain data (ids/ints),
/// resolvable against the theory library on demand.
public struct ModeReference: Codable, Equatable, Sendable {
    public var tonic: Int        // pitch class, 0...11
    public var scaleID: String   // ScaleLibrary.byID key, e.g. "dorian"

    public init(tonic: Int, scaleID: String) {
        self.tonic = tonic
        self.scaleID = scaleID
    }

    public func resolve() -> Mode? {
        guard let scale = ScaleLibrary.byID(scaleID) else { return nil }
        return Mode(tonic: PitchClass(tonic), scale: scale)
    }
}

/// A lightweight, Codable pointer to a `Chord` from MusicTheoryKit's `ChordVocabulary`.
public struct ChordReference: Codable, Equatable, Sendable {
    public var root: Int             // pitch class, 0...11
    public var chordTemplateID: String   // ChordVocabulary.byID key, e.g. "Ma7"

    public init(root: Int, chordTemplateID: String) {
        self.root = root
        self.chordTemplateID = chordTemplateID
    }

    public func resolve() -> Chord? {
        guard let template = ChordVocabulary.byID(chordTemplateID) else { return nil }
        return Chord(root: PitchClass(root), template: template)
    }
}

/// A move from the current section mode into a new one, anchored on shared pivot chords.
public struct ModeTransition: Codable, Equatable, Sendable {
    public var toMode: ModeReference
    public var pivotChords: [ChordReference]
    public var atMeasure: Int

    public init(toMode: ModeReference, pivotChords: [ChordReference], atMeasure: Int) {
        self.toMode = toMode
        self.pivotChords = pivotChords
        self.atMeasure = atMeasure
    }
}

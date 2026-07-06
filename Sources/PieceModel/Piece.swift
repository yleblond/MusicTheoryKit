import Foundation
import MusicTheoryKit

/// The top-level representation of a composition/improvisation, closely following the
/// JSON specification drafted in "Mode B.full.docx": global metadata, a library of named
/// reusable melodic fragments, and an ordered list of sections.
public struct Piece: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var composer: String?
    public var timeSignature: TimeSignature
    public var tempoBPM: Double
    public var key: ModeReference
    public var rhythmStructure: RhythmStructure
    public var fragments: [MelodicFragment]
    public var sections: [Section]

    public init(
        id: String = UUID().uuidString,
        title: String,
        composer: String? = nil,
        timeSignature: TimeSignature = .commonTime,
        tempoBPM: Double,
        key: ModeReference,
        rhythmStructure: RhythmStructure = RhythmStructure(),
        fragments: [MelodicFragment] = [],
        sections: [Section] = []
    ) {
        self.id = id
        self.title = title
        self.composer = composer
        self.timeSignature = timeSignature
        self.tempoBPM = tempoBPM
        self.key = key
        self.rhythmStructure = rhythmStructure
        self.fragments = fragments
        self.sections = sections
    }

    public func fragment(id fragmentID: String) -> MelodicFragment? {
        fragments.first { $0.id == fragmentID }
    }
}

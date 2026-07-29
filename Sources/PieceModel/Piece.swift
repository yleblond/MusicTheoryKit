import Foundation
import MusicTheoryKit
import SwiftData

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

/// The SwiftData-backed counterpart of `Piece` — same split as `LLMConnectionRecord`/
/// `LLMConnection` and `SoundTrackRecord`/`SoundTrack`: the stable value type stays exactly
/// what the rest of the app already works with, this type only exists to give it a
/// CloudKit-syncable row (see `ImprovSession.migratePiecesFromJSONIfNeeded`). `Piece` already
/// has its own stable `id` — reused as-is, no synthesized UUID needed (unlike `Scene`/
/// `GuideSequence`, which have none). Encoding the whole nested tree (Section → Track →
/// MelodyEvent/FragmentPlacement, plus the fragment library) as one blob avoids modeling 5+
/// levels of nesting as SwiftData relationships — nothing in this app queries into a Piece's
/// nested fields independently of loading the whole piece.
@Model
public final class PieceRecord {
    public var id: String = ""
    public var title: String = ""
    public var encodedPiece: Data = Data()

    public init(_ piece: Piece) {
        id = piece.id
        title = piece.title
        encodedPiece = (try? JSONEncoder().encode(piece)) ?? Data()
    }

    public var asPiece: Piece? {
        try? JSONDecoder().decode(Piece.self, from: encodedPiece)
    }
}

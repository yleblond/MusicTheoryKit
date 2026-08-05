import Foundation
import MusicTheoryKit
import SwiftData

/// The on-disk shape of `chords.json` — a flat list under one key, same convention as
/// `ChordProgressionTemplateFile`/`chordprogressions.json`. Lets a user add chord qualities
/// beyond `ChordVocabulary.seed` (e.g. altered/extended tensions not worth shipping in the
/// core) without a code change — see `ImprovSession.migrateChordTemplatesFromJSONIfNeeded`.
struct ChordTemplateFile: Codable {
    var chords: [ChordTemplate]
}

/// The SwiftData-backed counterpart of `ChordTemplate` — see `ChordProgressionTemplateRecord`'s
/// doc comment for the split rationale shared by every settings record in this migration wave.
@Model
final class ChordTemplateRecord {
    var id: String = ""
    var intervalsFromRoot: [Int] = []
    /// Preserves list order across a fetch — see `ChordProgressionTemplateRecord.sortOrder`.
    var sortOrder: Int = 0

    init(_ template: ChordTemplate, sortOrder: Int) {
        id = template.id
        intervalsFromRoot = template.intervalsFromRoot
        self.sortOrder = sortOrder
    }

    var asChordTemplate: ChordTemplate {
        ChordTemplate(id: id, intervalsFromRoot: intervalsFromRoot)
    }
}

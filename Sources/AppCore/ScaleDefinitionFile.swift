import Foundation
import MusicTheoryKit
import SwiftData

/// The on-disk shape of `scales.json` — a flat list under one key, same convention as
/// `ChordTemplateFile`/`chords.json`. Only lets a user add new `ScaleDefinition`s *within* an
/// existing `ScaleFamily` (`familyID` must reference one of the 7 fixed families) — a family's
/// own `basePattern` stays a hardcoded invariant, too structural to hand-edit safely via JSON.
struct ScaleDefinitionFile: Codable {
    var scales: [ScaleDefinition]
}

/// The SwiftData-backed counterpart of `ScaleDefinition` — see `ChordTemplateRecord`'s doc
/// comment for the split rationale shared by every settings record in this migration wave.
@Model
final class ScaleDefinitionRecord {
    var id: String = ""
    var familyID: Int = 1
    var degree: Int = 1
    var popularName: String = ""
    var systematicName: String = ""
    var chordSymbols: [String] = []
    /// Preserves list order across a fetch — see `ChordProgressionTemplateRecord.sortOrder`.
    var sortOrder: Int = 0

    init(_ scale: ScaleDefinition, sortOrder: Int) {
        id = scale.id
        familyID = scale.familyID
        degree = scale.degree
        popularName = scale.popularName
        systematicName = scale.systematicName
        chordSymbols = scale.chordSymbols
        self.sortOrder = sortOrder
    }

    var asScaleDefinition: ScaleDefinition {
        ScaleDefinition(
            id: id, familyID: familyID, degree: degree,
            popularName: popularName, systematicName: systematicName, chordSymbols: chordSymbols
        )
    }
}

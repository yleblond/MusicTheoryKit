import MusicTheoryKit
import SwiftData

/// The SwiftData-backed singleton holding which `NotationStyle` (`MusicTheoryKit`) is active —
/// mirrors `Localization.LanguageSettingRecord`'s own shape/rationale exactly: a single current
/// choice, not a flat list like `ChordProgressionTemplateRecord`. `styleID` is the raw
/// `NotationStyle.id` string, not the style itself, so adding a new style never requires a
/// schema migration.
@Model
final class NotationStyleSettingRecord {
    var styleID: String = "angloAmerican"

    init(_ styleID: String) {
        self.styleID = styleID
    }
}

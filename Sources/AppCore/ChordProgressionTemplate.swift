import Foundation
import MusicTheoryKit
import PieceModel

/// A named, mode-independent chord progression written in roman-numeral degree notation (see
/// `MusicTheoryKit.RomanNumeralChord` for the exact parsing rules) — e.g. `["I", "IV", "V", "I"]`.
/// Resolved against an actual `Mode` only when attached to a guide step (see
/// `ImprovSession.resolveChordProgression`), never stored pre-resolved here — the same template
/// can be applied to any tonic/mode.
public struct ChordProgressionTemplate: Codable, Equatable, Sendable {
    public var name: String
    public var degrees: [String]

    public init(name: String, degrees: [String]) {
        self.name = name
        self.degrees = degrees
    }

    /// Seeded into a fresh `chordprogressions.json` the first time none exists (see
    /// `ImprovSession.loadOrCreateChordProgressionTemplates`) — a handful of standard
    /// progressions (blues, jazz, pop, minor/rock) to have something to pick from
    /// immediately, editable/extendable by hand afterward.
    public static let builtInDefaults: [ChordProgressionTemplate] = [
        ChordProgressionTemplate(name: "Blues 12 mesures", degrees: [
            "I", "I", "I", "I", "IV", "IV", "I", "I", "V", "IV", "I", "I",
        ]),
        ChordProgressionTemplate(name: "ii-V-I (jazz)", degrees: ["ii", "V", "I"]),
        ChordProgressionTemplate(name: "Pop (I-V-vi-IV)", degrees: ["I", "V", "vi", "IV"]),
        ChordProgressionTemplate(name: "Annees 50 (I-vi-IV-V)", degrees: ["I", "vi", "IV", "V"]),
        ChordProgressionTemplate(name: "Canon (I-V-vi-iii-IV-I-IV-V)", degrees: [
            "I", "V", "vi", "iii", "IV", "I", "IV", "V",
        ]),
        ChordProgressionTemplate(name: "Cadence andalouse (i-VII-VI-V)", degrees: ["i", "VII", "VI", "V"]),
        ChordProgressionTemplate(name: "Progression circulaire (vi-ii-V-I)", degrees: ["vi", "ii", "V", "I"]),
        ChordProgressionTemplate(name: "Rock mineur (i-VI-III-VII)", degrees: ["i", "VI", "III", "VII"]),
    ]
}

/// The on-disk shape of `chordprogressions.json` — a flat list under one key, same convention
/// as `ColorPaletteFile`/`palettes.json` (a handful of named templates to pick from, not a
/// document per file).
struct ChordProgressionTemplateFile: Codable {
    var progressions: [ChordProgressionTemplate]
}

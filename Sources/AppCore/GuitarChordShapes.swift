import MusicTheoryKit

/// Standard tuning, movable "E-shape" barre chords — the root note always falls on the 6th
/// (low E) string, so any `ChordReference` with a covered `chordTemplateID` can be shown at
/// exactly one fret position by sliding this same hand shape up/down the neck. This is NOT
/// every possible guitar voicing for a chord (most qualities have several), just the single
/// most commonly-taught movable shape — chosen because it needs only one shape per quality
/// to cover all 12 roots, rather than a shape per root.
///
/// Each of the 12 covered shapes below was independently verified two ways before being
/// encoded (2026-07-21): (1) cross-checked against real chord-chart sources (jguitar.com,
/// guitar-chord.org, justinguitar.com lesson references) via a research pass, and (2) the
/// resulting fret pattern's actual sounded pitch classes were hand-verified against
/// `ChordVocabulary`'s own `intervalsFromRoot` for that quality (e.g. the major shape's 6
/// strings sound exactly {root, major 3rd, perfect 5th} relative to the root, nothing else)
/// — getting a guitarist wrong fingering data would be actively misleading, so both checks
/// mattered before trusting this table, not just one.
///
/// `Ma7#5` is deliberately NOT covered: no standard 6-string E-shape barre chord for it turned
/// up in the research pass (a self-derived shape satisfying the right pitch classes exists,
/// but wasn't cross-checked against an external source, so it's left out rather than shipped
/// on unverified confidence — see `shape(forRoot:chordTemplateID:)`'s `nil` return for this
/// and any other unknown `chordTemplateID`).
///
/// `mi7b5` and `dim7` ARE covered here as full 6-string E-shapes (verified correct), but real
/// guitar pedagogy more commonly teaches these two as compact 4-string voicings rooted on the
/// A or D string instead — this E-shape is a valid, playable, but less typically-taught
/// alternative for those two specifically, not "the" standard the way it is for the other 10.
public enum GuitarChordShape {
    /// One entry per string, index 0 = string 6 (low E, the root string) ... index 5 =
    /// string 1 (high e). `fret` is relative to the barre (0 = the barre fret itself); `nil`
    /// means that string is muted/not played. `finger` is 1 (the barre) through 4, `nil`
    /// only when the string itself is muted.
    public struct StringPosition: Equatable, Sendable {
        public let relativeFret: Int?
        public let finger: Int?
    }

    /// A single movable shape, plus the absolute barre fret it's been transposed to for one
    /// specific root — `positions[i].relativeFret + barreFret` (when non-nil) is the actual
    /// fret to show/play on string `6 - i`.
    public struct Diagram: Equatable, Sendable {
        public let label: String
        public let barreFret: Int
        public let positions: [StringPosition]
    }

    /// string6...string1, e.g. `[0, 2, 2, 1, 0, 0]` for major.
    private static func shape(frets: [Int?], fingers: [Int?]) -> [StringPosition] {
        zip(frets, fingers).map { StringPosition(relativeFret: $0, finger: $1) }
    }

    private static let shapesByTemplateID: [String: [StringPosition]] = [
        "Ma": shape(frets: [0, 2, 2, 1, 0, 0], fingers: [1, 3, 4, 2, 1, 1]),
        "mi": shape(frets: [0, 2, 2, 0, 0, 0], fingers: [1, 3, 4, 1, 1, 1]),
        "7": shape(frets: [0, 2, 0, 1, 0, 0], fingers: [1, 3, 1, 2, 1, 1]),
        "Ma7": shape(frets: [0, 2, 1, 1, 0, 0], fingers: [1, 3, 2, 2, 1, 1]),
        "mi7": shape(frets: [0, 2, 0, 0, 0, 0], fingers: [1, 3, 1, 1, 1, 1]),
        "mi7b5": shape(frets: [0, 1, 0, 3, 3, 3], fingers: [1, 2, 1, 3, 3, 3]),
        "dim7": shape(frets: [0, 1, 2, 0, 2, 0], fingers: [1, 2, 3, 1, 4, 1]),
        "aug": shape(frets: [0, 3, 2, 1, 1, 0], fingers: [1, 4, 3, 2, 2, 1]),
        "dim": shape(frets: [0, 1, 2, 0, nil, nil], fingers: [1, 2, 3, 1, nil, nil]),
        "miMa7": shape(frets: [0, 2, 1, 0, 0, 0], fingers: [1, 3, 2, 1, 1, 1]),
        "7#5": shape(frets: [0, 3, 0, 1, 1, 0], fingers: [1, 4, 1, 2, 2, 1]),
        "7b5": shape(frets: [0, 1, 0, 1, 3, 0], fingers: [1, 2, 1, 3, 4, 1]),
    ]

    /// `nil` if `chordTemplateID` isn't one of the 12 covered qualities (see this enum's own
    /// doc comment for why `Ma7#5` specifically is excluded) — callers should show a "no
    /// standard position" message for that case rather than guessing a voicing.
    public static func diagram(forRoot root: Int, chordTemplateID: String) -> Diagram? {
        guard let positions = shapesByTemplateID[chordTemplateID] else { return nil }
        // String 6 (low E) sounds pitch class 4 (E) open — the barre fret is how far above
        // that the root needs to move, e.g. root F (pitch class 5) -> fret 1, root G (7) ->
        // fret 3, matching the real, commonly-known positions for "the F/G barre chord".
        let barreFret = (((root % 12) + 12) % 12 - 4 + 12) % 12
        return Diagram(label: chordDisplayLabel(root: root, chordTemplateID: chordTemplateID), barreFret: barreFret, positions: positions)
    }

    private static func chordDisplayLabel(root: Int, chordTemplateID: String) -> String {
        "\(PitchClass(root).name())\(chordTemplateID)"
    }
}

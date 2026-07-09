/// Which of the 3 fixed rings a `CircleOfFifthsCell` belongs to — always major (innermost),
/// minor (middle), or diminished (outermost), regardless of column or selected tonic.
public enum ChordQuality: String, Codable, Sendable {
    case major, minor, diminished
}

/// Purely a visual/accessibility distinction (matches the physical wheel this is modeled on,
/// where shapes alternate by semitone so colorblind users have a second way to tell adjacent
/// notes apart) — carries no musical meaning.
public enum ChordShape: String, Codable, Sendable {
    case square, circle
}

/// One of the 3 fixed-quality chords stacked at a `CircleOfFifthsColumn` — **not** all rooted
/// on the column's own pitch class: only the major (ring1) cell is; the minor (ring2) cell is
/// the column's *relative minor* (a minor third below), and the diminished (ring3) cell is
/// its *leading-tone diminished* (a semitone below) — e.g. the column for C carries a major
/// cell rooted on C ("C", "I"), a minor cell rooted on A ("Am", "vi"), and a diminished cell
/// rooted on B ("B°", "vii°"). This is what makes the 7 diatonic chords of one key show up
/// stacked in the SAME 3 columns (tonic and its two fifths-neighbors) across all 3 rings,
/// rather than spread across 7 different columns.
public struct CircleOfFifthsCell: Equatable, Sendable {
    /// This cell's own chord root — NOT necessarily the column's `pitchClass` (see above).
    public let pitchClass: PitchClass
    public let quality: ChordQuality
    /// Alternates by `pitchClass` parity (own root, not the column's) — a visual/accessibility
    /// distinction matching the physical wheel this is modeled on, no musical meaning.
    public let shape: ChordShape
    /// `ChordVocabulary` id for a plain triad of this quality: "Ma", "mi", or "dim".
    public let chordTemplateID: String
    /// The scale-degree label relative to `wheel(tonic:activeTonic:)`'s `activeTonic` (the
    /// mode actually being played — "I" always lands on ITS tonic, not the parent's), cased/
    /// marked by quality: uppercase plain for major ("IV", "bVII"), lowercase plain for minor
    /// ("ii", "bvi"), lowercase with "°" for diminished ("vii°", "iv°").
    public let relativeDegree: String
    /// Whether this cell's chord is one of the 7 diatonic chords of the wheel's `tonic`
    /// treated as a major scale — the "grouping layer" highlight.
    public let isDiatonic: Bool
}

/// One of the wheel's 12 fixed physical positions (by ascending fifths) — never moves
/// regardless of which `tonic` `CircleOfFifths.wheel(tonic:)` is built for; only `modeName`
/// and each cell's `relativeDegree`/`isDiatonic` are recomputed relative to that tonic.
public struct CircleOfFifthsColumn: Equatable, Sendable {
    public let pitchClass: PitchClass
    /// NOT "the church mode you get by treating this column as tonic" — each of the 7 church
    /// modes is glued at a fixed offset from `activeTonic` equal to the interval up to its own
    /// parent (see `modeNamesBySemitoneOffset`), so this is non-nil on 7 columns that are
    /// largely *not* the diatonic ones (only I/IV/V coincide) — the active mode's own name
    /// always lands on the parent's column, doubling as "rotate the selector here" guidance.
    public let modeName: String?
    /// Always 3, in fixed ring order: major, minor, diminished — each cell's own chord root
    /// may differ from this column's `pitchClass` (see `CircleOfFifthsCell`).
    public let cells: [CircleOfFifthsCell]
}

/// The always-available 12-column x 3-ring chord palette, arranged by fifths — a fixed,
/// tonic-independent "universe" of chords (every root's major/minor/diminished triad), with
/// `tonic` determining which 7 columns are diatonic (and their relative-degree labels/mode
/// names) without changing the palette itself.
public struct CircleOfFifthsWheel: Equatable, Sendable {
    public let tonic: PitchClass
    /// Always 12, in fixed ascending-fifths order starting at C (C, G, D, A, E, B, F#, Db,
    /// Ab, Eb, Bb, F) — this physical order never depends on `tonic`.
    public let columns: [CircleOfFifthsColumn]
    /// Index into `columns` where `pitchClass == tonic`.
    public let activeColumnIndex: Int
}

public enum CircleOfFifths {
    /// The 12 pitch classes in fixed ascending-fifths order starting at C — the wheel's
    /// unchanging physical layout.
    private static let physicalOrder: [Int] = (0..<12).map { (7 * $0) % 12 }

    /// Degree label by semitone offset from tonic (0...11) — major-ring spelling. Each ring
    /// has its own spelling convention on the physical wheel this is modeled on (the tritone
    /// is "bV" here but "#iv°" on the diminished ring; offsets 1 and 8 are "bII"/"bVI" here
    /// but "#i"/"#v" on the minor ring) — this table is major-only, see `minorDegreeLabels`/
    /// `diminishedDegreeLabels` for the other two rings.
    private static let majorDegreeLabels = ["I", "bII", "II", "bIII", "III", "IV", "bV", "V", "bVI", "VI", "bVII", "VII"]
    /// Minor-ring spelling — NOT simply `majorDegreeLabels` lowercased: offsets 1, 6, 8 use
    /// sharps here (#i, #iv, #v) where the major ring uses flats.
    private static let minorDegreeLabels = ["i", "#i", "ii", "biii", "iii", "iv", "#iv", "v", "#v", "vi", "bvii", "vii"]
    /// Diminished-ring spelling — sharps for every accidental offset, matching neither of the
    /// other two rings' mix of sharps and flats.
    private static let diminishedDegreeLabels = [
        "i\u{00B0}", "#i\u{00B0}", "ii\u{00B0}", "#ii\u{00B0}", "iii\u{00B0}", "iv\u{00B0}",
        "#iv\u{00B0}", "v\u{00B0}", "#v\u{00B0}", "vi\u{00B0}", "#vi\u{00B0}", "vii\u{00B0}",
    ]
    private static let majorDiatonicOffsets: Set<Int> = [0, 5, 7]   // I, IV, V
    private static let minorDiatonicOffsets: Set<Int> = [2, 4, 9]  // ii, iii, vi
    private static let diminishedDiatonicOffset = 11               // vii°
    /// Mode name by semitone offset from tonic — NOT "which mode do you get treating this
    /// column as tonic within the parent" (that would put Lydian at offset 5, its own tonic).
    /// It's "the interval FROM that mode's own tonic UP TO the parent tonic" (Lydian's parent
    /// sits a fifth above Lydian's own tonic, so "Lydian" is printed at the "V" position) —
    /// this is what lets rotating the ring to a mode's printed name double as "now find the
    /// parent, to align the chord selector to" on the physical wheel this is modeled on.
    private static let modeNamesBySemitoneOffset: [Int: String] = [
        0: "Ionian", 7: "Lydian", 1: "Locrian", 8: "Phrygian", 3: "Aeolian", 10: "Dorian", 5: "Mixolydian",
    ]

    /// Semitone offset from a column's own pitch class to each ring's actual chord root:
    /// major is rooted on the column itself; minor is its relative minor (-3 semitones,
    /// i.e. +9); diminished is its leading-tone diminished (-1 semitone, i.e. +11).
    private static let rootOffsetByQuality: [ChordQuality: Int] = [.major: 0, .minor: 9, .diminished: 11]

    /// Builds the wheel for a given `tonic` — always succeeds (unlike the old family-1-only
    /// API this replaces): the palette itself needs no mode/family at all, only the
    /// diatonic-highlight layer is "as if `tonic` were a major scale", which is true for any
    /// pitch class. `tonic` here is always the *parent* major key (e.g. E for "A Lydian") — it
    /// alone decides which 7 cells are diatonic, independent of which of that key's 7 modes is
    /// actually being played (all 7 share the same parent and the same 7 diatonic chords).
    ///
    /// `activeTonic` (defaults to `tonic` — i.e. Ionian) is the mode actually being played (A,
    /// not E, for "A Lydian") and controls both `relativeDegree` ("I" always lands on
    /// `activeTonic`'s own column) AND `modeName`: each mode name is glued at a fixed offset
    /// from `activeTonic` equal to the interval *up to its own parent* (see
    /// `modeNamesBySemitoneOffset`), so — by construction — the active mode's own name always
    /// ends up on the parent's column, i.e. exactly where the diatonic highlight is centered.
    /// Conflating `activeTonic` with `tonic` used to put "I" on the *parent's* tonic regardless
    /// of which mode was selected — correct for Ionian (where they're the same pitch class)
    /// but increasingly wrong the further a mode sits from its parent (off by one degree for
    /// Lydian/Mixolydian, all the way round for Locrian).
    public static func wheel(tonic: PitchClass, activeTonic: PitchClass? = nil) -> CircleOfFifthsWheel {
        let degreeTonic = activeTonic ?? tonic
        let columns = physicalOrder.map { pc -> CircleOfFifthsColumn in
            let modeNameOffset = (pc - degreeTonic.value + 12) % 12
            let cells = [ChordQuality.major, .minor, .diminished].map { quality -> CircleOfFifthsCell in
                let root = (pc + rootOffsetByQuality[quality]!) % 12
                let diatonicOffset = (root - tonic.value + 12) % 12
                let degreeOffset = (root - degreeTonic.value + 12) % 12
                let (templateID, degree, isDiatonic): (String, String, Bool)
                switch quality {
                case .major: (templateID, degree, isDiatonic) = ("Ma", majorDegreeLabels[degreeOffset], majorDiatonicOffsets.contains(diatonicOffset))
                case .minor: (templateID, degree, isDiatonic) = ("mi", minorDegreeLabels[degreeOffset], minorDiatonicOffsets.contains(diatonicOffset))
                case .diminished: (templateID, degree, isDiatonic) = ("dim", diminishedDegreeLabels[degreeOffset], diatonicOffset == diminishedDiatonicOffset)
                }
                return CircleOfFifthsCell(pitchClass: PitchClass(root), quality: quality, shape: root % 2 == 0 ? .square : .circle, chordTemplateID: templateID, relativeDegree: degree, isDiatonic: isDiatonic)
            }
            return CircleOfFifthsColumn(pitchClass: PitchClass(pc), modeName: modeNamesBySemitoneOffset[modeNameOffset], cells: cells)
        }
        let activeColumnIndex = columns.firstIndex { $0.pitchClass == tonic }!
        return CircleOfFifthsWheel(tonic: tonic, columns: columns, activeColumnIndex: activeColumnIndex)
    }

    /// The parent major-key tonic for `mode` — `nil` unless `mode.scale.familyID == 1` (only
    /// the classic 7 "Major Modes" have a well-defined parent major key/mode-name mapping;
    /// `wheel(tonic:)`'s 36-cell palette itself needs no such restriction, but the
    /// mode-name/diatonic-highlight layer is specifically about treating some pitch class as
    /// a major-scale tonic, which callers use this to find from an arbitrary `Mode`).
    public static func parentTonic(for mode: Mode) -> PitchClass? {
        guard mode.scale.familyID == 1, let ionian = ScaleLibrary.byID("ionian") else { return nil }
        let ionianOffsets = ionian.pitchClassesFromRoot // [0,2,4,5,7,9,11], index+1 = degree
        let offsetFromParent = ionianOffsets[mode.scale.degree - 1]
        return mode.tonic + (-offsetFromParent)
    }
}

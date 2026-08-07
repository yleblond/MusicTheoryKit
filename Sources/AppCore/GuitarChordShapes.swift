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

        /// Public so a caller outside this module (e.g. `JamShackUI`'s
        /// `GuitarChordDiagramView`, converting a `WebConsoleGuitarChordDiagram` back into a
        /// real `Diagram` for offline/in-process rendering) can build one directly instead of
        /// only ever receiving values already constructed by `diagram(forRoot:chordTemplateID:)`.
        public init(relativeFret: Int?, finger: Int?) {
            self.relativeFret = relativeFret
            self.finger = finger
        }
    }

    /// A single movable shape, plus the absolute barre fret it's been transposed to for one
    /// specific root — `positions[i].relativeFret + barreFret` (when non-nil) is the actual
    /// fret to show/play on string `6 - i`.
    public struct Diagram: Equatable, Sendable {
        public let label: String
        public let barreFret: Int
        public let positions: [StringPosition]
        /// `true` when this diagram is a root-position fallback shown in place of a genuine
        /// inversion shape that either doesn't exist yet (most qualities beyond "Ma"/"mi") or
        /// wasn't requested (`inversion == 0`) — see `diagram(forRoot:chordTemplateID:inversion:)`.
        /// A caller should show a "position de base" annotation when this is `true` and the
        /// caller actually asked for `inversion > 0`.
        public let isBasePositionFallback: Bool

        /// See `StringPosition.init`'s doc comment for why this needs to be public.
        public init(label: String, barreFret: Int, positions: [StringPosition], isBasePositionFallback: Bool = false) {
            self.label = label
            self.barreFret = barreFret
            self.positions = positions
            self.isBasePositionFallback = isBasePositionFallback
        }
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

    /// A single string's fixed offset from a shape's own `barreFret` anchor, plus a suggested
    /// finger — see `triadInversionShapesByTemplateID`'s doc comment for how these were derived.
    private struct TriadInversionShape {
        /// Added to the root's own pitch class (mod 12) to get this shape's `barreFret` — see
        /// this file's own inversion doc comment for the derivation.
        let barreFretOffset: Int
        /// Index 2 = string 4 (D), index 3 = string 3 (G), index 4 = string 2 (B) — strings 6,
        /// 5, 1 (indices 0, 1, 5) are always muted for these compact 3-string shapes.
        let dGBRelativeFrets: (d: Int, g: Int, b: Int)
        let dGBFingers: (d: Int, g: Int, b: Int)
    }

    /// Genuine 1st/2nd-inversion shapes for the "Ma"/"mi" triads only (per the Chord Library's
    /// confirmed scope: triads and 7th chords up to the 3rd inversion, 7th-chord inversions
    /// deferred as a followup — a triad only has a 1st and 2nd inversion to begin with).
    ///
    /// These are NOT a re-ordering of `shapesByTemplateID`'s own 6-string barre shape (a real
    /// guitarist doesn't invert a 6-string chord by moving notes around on the same 6 strings —
    /// they switch to a different, more compact shape). Instead this is the standard "3 notes
    /// on 3 adjacent strings" triad voicing taught for inversions, here on the D-G-B string set
    /// (open pitch classes D=2, G=7, B=11).
    ///
    /// Derivation/verification: the major-triad root-position shape below (D=root+2,
    /// G=root+1, B=root, i.e. barreFret = (root - 4 + 12) % 12) was checked against a real
    /// fretted example (C major: D-string fret 10 = C, G-string fret 9 = E, B-string fret 8 =
    /// G) from a published lesson (weissguitar.com, "Major Triad Shapes" D-G-B string set,
    /// 2026-08 research pass) and matches exactly. The other 5 shapes (major 1st/2nd inversion,
    /// minor root/1st/2nd inversion) were derived with the identical note-by-note arithmetic
    /// (each string's fret = target pitch class minus that string's own open pitch class, mod
    /// 12) and cross-checked by confirming every string's resulting note is the correct chord
    /// tone — not independently verified against a second external source the way the
    /// 6-string barre table above was. Finger numbers are a reasonable ascending-by-fret
    /// suggestion, not sourced from a lesson reference.
    private static let triadInversionShapesByTemplateID: [String: [Int: TriadInversionShape]] = [
        "Ma": [
            1: TriadInversionShape(barreFretOffset: 0, dGBRelativeFrets: (d: 2, g: 0, b: 1), dGBFingers: (d: 3, g: 1, b: 2)),
            2: TriadInversionShape(barreFretOffset: 5, dGBRelativeFrets: (d: 0, g: 0, b: 0), dGBFingers: (d: 1, g: 1, b: 1)),
        ],
        "mi": [
            1: TriadInversionShape(barreFretOffset: 0, dGBRelativeFrets: (d: 1, g: 0, b: 1), dGBFingers: (d: 2, g: 1, b: 3)),
            2: TriadInversionShape(barreFretOffset: 4, dGBRelativeFrets: (d: 1, g: 1, b: 0), dGBFingers: (d: 2, g: 3, b: 1)),
        ],
    ]

    /// A specific inversion's diagram (0 = root position, identical to
    /// `diagram(forRoot:chordTemplateID:)`) — falls back to the root-position E-shape diagram,
    /// with `Diagram.isBasePositionFallback` set, whenever `inversion > 0` isn't covered by
    /// `triadInversionShapesByTemplateID` (every quality besides "Ma"/"mi", or an inversion
    /// index a triad doesn't have). `nil` only when even the root-position fallback has no
    /// diagram (same cases `diagram(forRoot:chordTemplateID:)` already returns `nil` for).
    public static func diagram(forRoot root: Int, chordTemplateID: String, inversion: Int) -> Diagram? {
        guard inversion > 0 else { return diagram(forRoot: root, chordTemplateID: chordTemplateID) }
        let pitchClass = (((root % 12) + 12) % 12)
        let label = chordDisplayLabel(root: root, chordTemplateID: chordTemplateID)
        if let shape = triadInversionShapesByTemplateID[chordTemplateID]?[inversion] {
            let barreFret = (pitchClass + shape.barreFretOffset) % 12
            let positions: [StringPosition] = [
                StringPosition(relativeFret: nil, finger: nil), // string 6, low E — muted
                StringPosition(relativeFret: nil, finger: nil), // string 5, A — muted
                StringPosition(relativeFret: shape.dGBRelativeFrets.d, finger: shape.dGBFingers.d), // string 4, D
                StringPosition(relativeFret: shape.dGBRelativeFrets.g, finger: shape.dGBFingers.g), // string 3, G
                StringPosition(relativeFret: shape.dGBRelativeFrets.b, finger: shape.dGBFingers.b), // string 2, B
                StringPosition(relativeFret: nil, finger: nil), // string 1, high e — muted
            ]
            return Diagram(label: label, barreFret: barreFret, positions: positions)
        }
        guard let fallback = diagram(forRoot: root, chordTemplateID: chordTemplateID) else { return nil }
        return Diagram(label: fallback.label, barreFret: fallback.barreFret, positions: fallback.positions, isBasePositionFallback: true)
    }

    /// Whether `diagram(forRoot:chordTemplateID:inversion:)` has a genuine, distinct shape for
    /// this quality/inversion combination — `false` means that call would silently fall back to
    /// the root-position diagram (`isBasePositionFallback`). Lets a caller (the Chord Library's
    /// position picker) only offer positions that actually produce a different diagram, instead
    /// of a control that visibly does nothing when tapped for the ~20 qualities beyond "Ma"/"mi".
    public static func hasVerifiedInversionShape(chordTemplateID: String, inversion: Int) -> Bool {
        guard inversion > 0 else { return true }
        return triadInversionShapesByTemplateID[chordTemplateID]?[inversion] != nil
    }

    private static func chordDisplayLabel(root: Int, chordTemplateID: String) -> String {
        "\(PitchClass(root).name())\(chordTemplateID)"
    }
}

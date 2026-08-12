/// One of the 7 natural note letters — the diatonic identity a `SpelledPitch` is built from,
/// distinct from `PitchClass` (0...11): the letter alone, before any accidental, already picks
/// which staff line/space a note lives on and which of two enharmonically-equal spellings
/// (e.g. G#/Ab) is meant.
public enum NoteLetter: Int, CaseIterable, Hashable, Sendable {
    case C, D, E, F, G, A, B

    /// The pitch class of this letter with no accidental — C=0, D=2, E=4, F=5, G=7, A=9, B=11.
    public var naturalPitchClass: Int {
        [0, 2, 4, 5, 7, 9, 11][rawValue]
    }

    /// Position on the line of fifths for the NATURAL letter alone (no accidental) — F=-1, C=0,
    /// G=1, D=2, A=3, E=4, B=5, the standard ordering every circle-of-fifths/key-signature
    /// convention is built from (`MajorKeySignature`'s own sharp/flat order encodes the same
    /// sequence, just as pitch classes rather than named letters).
    public var lineOfFifths: Int {
        [0, 2, 4, -1, 1, 3, 5][rawValue]
    }
}

/// How far a spelling sits from natural — `rawValue` doubles as both the semitone offset and
/// (×7) the line-of-fifths offset, since a chromatic semitone and 7 fifths are octave-equivalent.
public enum Accidental: Int, Sendable {
    case doubleFlat = -2
    case flat = -1
    case natural = 0
    case sharp = 1
    case doubleSharp = 2

    public var semitoneOffset: Int { rawValue }
    public var lineOfFifthsOffset: Int { rawValue * 7 }

    /// The narrow glyph — "𝄫"/"♭"/""/"♯"/"𝄪" — `natural` is empty rather than "♮" since every
    /// caller so far only wants an accidental drawn/appended when there IS one.
    public var symbol: String {
        switch self {
        case .doubleFlat: return "\u{1D12B}"
        case .flat: return "\u{266D}"
        case .natural: return ""
        case .sharp: return "\u{266F}"
        case .doubleSharp: return "\u{1D12A}"
        }
    }
}

/// A note's real musical identity — letter + accidental + octave — as opposed to `PitchClass`
/// (0...11), which only ever answers "which of the 12 keys" and can't distinguish two
/// enharmonically-equal spellings (G#4 and Ab4 are the same `PitchClass`, 8, but different
/// `SpelledPitch`s). Introduced so the tuning engine can tell them apart where it musically
/// matters (Pythagorean/meantone-style temperaments built from an unbroken chain of fifths) —
/// see `Temperament.Model.lineOfFifths` and `DiatonicSpelling`, which resolves which spelling a
/// mode's own scale degrees use.
public struct SpelledPitch: Equatable, Sendable {
    public let letter: NoteLetter
    public let accidental: Accidental
    public let octave: Int

    public init(letter: NoteLetter, accidental: Accidental, octave: Int) {
        self.letter = letter
        self.accidental = accidental
        self.octave = octave
    }

    public var pitchClass: PitchClass {
        PitchClass(letter.naturalPitchClass + accidental.semitoneOffset)
    }

    /// This spelling's own position on the line of fifths — the quantity that actually
    /// distinguishes G# (8) from Ab (-4) even though both collapse to the same `pitchClass`.
    public var lineOfFifths: Int {
        letter.lineOfFifths + accidental.lineOfFifthsOffset
    }
}

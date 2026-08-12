/// Resolves the correct letter+accidental spelling for a mode's own 7 diatonic degrees — the
/// piece the tuning engine needs to tell G# from Ab where a temperament actually cares (see
/// `SpelledPitch`/`Temperament.Model.lineOfFifths`). This is priority-2 resolution from the
/// Intonations feature's own plan ("mode/gamme sélectionné") — the only context this app
/// currently has available; resolution by detected chord or by Guide (priorities 3/4) are future
/// work, see the project backlog.
public enum DiatonicSpelling {
    /// The canonical spelling of each of the 12 possible major-key tonics — matches the
    /// convention already implicit throughout this codebase (C, Db, D, Eb, E, F, F#, G, Ab, A,
    /// Bb, B — the same choices `MajorKeySignature.forMajorTonic` already bakes in: Db over C#,
    /// F# over Gb) and needed here as an actual (letter, accidental) pair rather than a display
    /// string, since it's the anchor the rest of a key's 7 letters are built from.
    private static let canonicalMajorTonicSpelling: [Int: (letter: NoteLetter, accidental: Accidental)] = [
        0: (.C, .natural), 1: (.D, .flat), 2: (.D, .natural), 3: (.E, .flat), 4: (.E, .natural),
        5: (.F, .natural), 6: (.F, .sharp), 7: (.G, .natural), 8: (.A, .flat), 9: (.A, .natural),
        10: (.B, .flat), 11: (.B, .natural),
    ]

    /// The same 12-entry canonical table above, exposed for any bare `PitchClass` (not just a
    /// major tonic) — `Temperament`'s line-of-fifths model falls back to this when it's asked for
    /// a `cents(for pitchClass:...)` with no real musical context to resolve a spelling from.
    public static func canonicalSpelling(forPitchClass pitchClass: PitchClass) -> SpelledPitch {
        let entry = canonicalMajorTonicSpelling[pitchClass.value] ?? (.C, .natural)
        return SpelledPitch(letter: entry.letter, accidental: entry.accidental, octave: 4)
    }

    private static let naturalLetterCycle: [NoteLetter] = [.C, .D, .E, .F, .G, .A, .B]

    /// `mode`'s own 7 diatonic degrees, each correctly spelled, in the mode's own degree order
    /// (index 0 = the mode's tonic) — `nil` for anything outside scale family 1 (the 7 classic
    /// modes, the only family with a well-defined parent major key signature, per
    /// `CircleOfFifths.parentTonic(for:)`, which this builds on). Octave is always 4 — this
    /// resolver only exists to disambiguate SPELLING for tuning purposes (octave-invariant); a
    /// caller that needs a real absolute pitch should combine `.pitchClass` with its own register.
    public static func spelledDegrees(for mode: Mode) -> [SpelledPitch]? {
        guard let parentTonic = CircleOfFifths.parentTonic(for: mode),
              let tonicSpelling = canonicalMajorTonicSpelling[parentTonic.value] else { return nil }
        let signature = MajorKeySignature.forMajorTonic(parentTonic.value)
        guard let startIndex = naturalLetterCycle.firstIndex(of: tonicSpelling.letter) else { return nil }

        let parentDegrees: [SpelledPitch] = (0..<7).map { step in
            let letter = naturalLetterCycle[(startIndex + step) % 7]
            let accidental: Accidental = signature.affectedLetters.contains(letter) ? signature.accidentalDirection : .natural
            return SpelledPitch(letter: letter, accidental: accidental, octave: 4)
        }

        guard let rotationIndex = parentDegrees.firstIndex(where: { $0.pitchClass == mode.tonic }) else { return nil }
        return Array(parentDegrees[rotationIndex...] + parentDegrees[..<rotationIndex])
    }
}

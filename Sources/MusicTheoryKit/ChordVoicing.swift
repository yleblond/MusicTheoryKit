/// A `Chord` rotated into a specific inversion — `orderedPitchClasses` lists the chord's own
/// pitch classes (no octave information, same as `Chord.pitchClasses`) starting from whichever
/// tone is the bass in this inversion, e.g. Cmaj7 (`[C, E, G, B]`) 2nd inversion is
/// `[G, B, C, E]`. This is a *reordering* only: turning it into an actual playable/notated
/// voicing (assigning real octaves so the bass truly sounds lowest) is the caller's job — see
/// the Chord Library screen, which anchors `orderedPitchClasses` at a fixed octave the same way
/// `ChordStaffView.chordEvent(root:tones:)` already anchors a root-position chord.
public struct ChordVoicing: Equatable, Sendable {
    public let chord: Chord
    /// Clamped into `0..<chord.pitchClasses.count` — see `Chord.voicing(inversion:)`.
    public let inversion: Int
    public let orderedPitchClasses: [PitchClass]

    public var bassPitchClass: PitchClass { orderedPitchClasses[0] }
}

public extension Chord {
    /// The highest inversion that makes sense for this chord's own tone count — a triad only
    /// has a 1st and 2nd inversion (`maxInversion == 2`), a 7th chord adds a 3rd, etc. Lets a
    /// UI bound its inversion picker per-chord instead of always offering a fixed 1...6.
    static func maxInversion(for template: ChordTemplate) -> Int {
        max(0, template.intervalsFromRoot.count - 1)
    }

    /// Rotates `pitchClasses` so the `inversion`-th chord tone (0 = root) becomes the bass —
    /// generic over any tone count (3 for a triad, 7+ for an extended chord), no per-chord
    /// special-casing. `inversion` wraps (via modulo) rather than trapping, so passing a value
    /// past `Chord.maxInversion(for:)` degrades to a lower inversion instead of crashing.
    func voicing(inversion: Int) -> ChordVoicing {
        let tones = pitchClasses
        guard !tones.isEmpty else { return ChordVoicing(chord: self, inversion: 0, orderedPitchClasses: []) }
        let clamped = ((inversion % tones.count) + tones.count) % tones.count
        let rotated = Array(tones[clamped...] + tones[..<clamped])
        return ChordVoicing(chord: self, inversion: clamped, orderedPitchClasses: rotated)
    }

    /// The inversion whose bass is `bassOverride`, for slash-chord support (`ChordEvent.bassOverride`)
    /// — `nil` if `bassOverride` isn't one of this chord's own tones (a non-chord-tone bass,
    /// e.g. "C/D", isn't an inversion at all and is left for the caller to render separately).
    func voicing(bassOverride: PitchClass) -> ChordVoicing? {
        guard let index = pitchClasses.firstIndex(of: bassOverride) else { return nil }
        return voicing(inversion: index)
    }
}

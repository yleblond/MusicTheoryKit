/// Places a sequence of pitch classes (0...11, in the order given — not necessarily ascending
/// as raw values themselves, e.g. a mode's own tonic-shifted degree order can wrap around 12)
/// into real ascending MIDI pitches, moving up an octave whenever needed to stay above the
/// previous one. The shared math behind the Chord/Mode/Progression Library's staff display and
/// audition playback alike: a chord's inversion voicing, a scale run, a progression's chord
/// sequence are all "place these pitch classes, in this order, ascending from some floor".
public enum PitchSequencing {
    public static func ascendingPitches(forPitchClasses pitchClasses: [Int], startingAbove floor: Int) -> [Int] {
        var pitches: [Int] = []
        var previous = floor
        for pitchClass in pitchClasses {
            let normalized = ((pitchClass % 12) + 12) % 12
            var pitch = (previous / 12) * 12 + normalized
            while pitch <= previous { pitch += 12 }
            pitches.append(pitch)
            previous = pitch
        }
        return pitches
    }
}

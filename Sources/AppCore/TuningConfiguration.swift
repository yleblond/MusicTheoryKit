import Foundation
import MusicTheoryKit
import SwiftData

/// The SwiftData-backed singleton holding the active Intonations setting — mirrors
/// `NotationStyleSettingRecord`'s own shape/rationale exactly: a single current choice, not a
/// flat list. `temperamentID` is the raw `Temperament.id` string, not the value itself, so adding
/// a new temperament never requires a schema migration. No tonic is stored here — see
/// `ImprovSession.contextualMode`'s own doc comment for why the tonic is derived live from
/// whichever Théorie screen is browsing a mode, not chosen independently on this setting.
@Model
final class TuningConfigurationRecord {
    var temperamentID: String = "equal"
    var referenceA4: Double = 440

    init(temperamentID: String, referenceA4: Double) {
        self.temperamentID = temperamentID
        self.referenceA4 = referenceA4
    }
}

/// Which temperament is active, plus the concert-pitch reference it's tuned against. Defaults
/// (`equal`/440) are acoustically a no-op — identical to the app's behavior before this setting
/// existed — so nobody who never opens Intonations hears any difference.
public struct TuningConfiguration: Equatable, Sendable {
    public var temperamentID: String
    public var referenceA4: Double

    public init(temperamentID: String = "equal", referenceA4: Double = 440) {
        self.temperamentID = temperamentID
        self.referenceA4 = referenceA4
    }
}

/// The cents correction for `pitchClass`, `tonic` semitones away from wherever `configuration`'s
/// temperament is anchored — 0 if `configuration.temperamentID` doesn't resolve to a known
/// `Temperament` (defensive default, not expected to happen with a UI-driven picker). Includes
/// the global reference-pitch offset (`referenceA4` vs. the standard 440 Hz every MIDI pitch
/// otherwise assumes), so retuning concert pitch is just another additive cents term.
public func fixedTemperamentCents(forPitchClass pitchClass: PitchClass, tonic: PitchClass, configuration: TuningConfiguration) -> Double {
    guard let temperament = TemperamentLibrary.byID(configuration.temperamentID) else { return 0 }
    let temperamentDeviation = TemperamentLibrary.cents(for: pitchClass, in: temperament, tonic: tonic)
    let referenceOffset = 1200 * log2(configuration.referenceA4 / 440)
    return temperamentDeviation + referenceOffset
}

/// The cents correction for `pitch`, resolving its real enharmonic spelling from `mode`'s own
/// diatonic degrees first (`DiatonicSpelling.spelledDegrees(for:)`) so a temperament built from
/// an unbroken chain of fifths (Pythagorean) can tell G# from Ab where the mode actually calls
/// for one specific spelling — priority-2 resolution from the Intonations feature's own plan
/// ("mode/gamme sélectionné"), the only context this app has today (chord-based and Guide-based
/// resolution are future work). Falls back to `fixedTemperamentCents(forPitchClass:tonic:)` for
/// any pitch outside the mode's own 7 degrees (a chromatic passing tone) or for a scale outside
/// family 1 (no well-defined parent key signature to spell from) — the explicit "politique par
/// défaut" the spec calls for rather than inventing a context that isn't there.
public func temperamentCents(forPitch pitch: Int, mode: Mode, configuration: TuningConfiguration) -> Double {
    let pitchClass = PitchClass(pitch)
    if let spelledDegrees = DiatonicSpelling.spelledDegrees(for: mode),
       let spelledPitch = spelledDegrees.first(where: { $0.pitchClass == pitchClass }),
       let tonicSpelling = spelledDegrees.first(where: { $0.pitchClass == mode.tonic }),
       let temperament = TemperamentLibrary.byID(configuration.temperamentID) {
        let temperamentDeviation = TemperamentLibrary.cents(for: spelledPitch, in: temperament, tonicSpelling: tonicSpelling)
        let referenceOffset = 1200 * log2(configuration.referenceA4 / 440)
        return temperamentDeviation + referenceOffset
    }
    return fixedTemperamentCents(forPitchClass: pitchClass, tonic: mode.tonic, configuration: configuration)
}

/// Absolute frequency in Hz for `midiPitch` (A4 = MIDI 69 = 440Hz), plus a `cents` correction —
/// typically the output of `fixedTemperamentCents`/`temperamentCents`, which already folds in
/// both the temperament's own deviation AND the reference-pitch offset (`referenceA4` vs. the
/// standard 440 baked in here), so this function itself never needs its own `referenceA4`
/// parameter. Unlike `SpectrogramView`'s own private MIDI→Hz helper (fixed to 440Hz, no cents),
/// this is the actual sounding frequency a pitch resolves to under a specific
/// `TuningConfiguration` — what `OctaveSpectrumGrid`'s dissonance landscape is built from.
public func hz(forMidiPitch midiPitch: Int, cents: Double = 0) -> Double {
    440.0 * pow(2.0, (Double(midiPitch) - 69.0) / 12.0) * pow(2.0, cents / 1200.0)
}

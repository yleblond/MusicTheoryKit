import Foundation
import MusicTheoryKit
import SwiftData

/// The SwiftData-backed singleton holding the active Intonations setting — mirrors
/// `NotationStyleSettingRecord`'s own shape/rationale exactly: a single current choice, not a
/// flat list. `temperamentID` is the raw `Temperament.id` string, not the value itself, so adding
/// a new temperament never requires a schema migration. No tonic is stored here — see
/// `ImprovSession.contextualTonic`'s own doc comment for why the tonic is derived live from
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

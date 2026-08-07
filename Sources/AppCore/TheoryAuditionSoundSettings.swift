import SwiftData

/// The SwiftData-backed singleton holding which `FavoriteSound` (by id) the Théorie screens'
/// audition playback uses — mirrors `NotationStyleSettingRecord`'s own shape exactly. `soundID`
/// is optional since there may be none yet (a fresh install, or the previously-picked sound
/// having been un-favorited since) — see `ImprovSession.theoryAuditionSound()` for the fallback.
@Model
final class TheoryAuditionSoundSettingRecord {
    var soundID: String?

    init(_ soundID: String?) {
        self.soundID = soundID
    }
}

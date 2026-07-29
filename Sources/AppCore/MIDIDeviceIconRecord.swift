import Foundation
import SwiftData

/// The one object kind of the four icon-assignable ones (scene/role/favorite instrument/MIDI
/// keyboard) with no existing persisted identity to hang an icon off — `TrackInfo`/`TrackID` are
/// rebuilt fresh from live CoreMIDI enumeration every launch, never `Codable`, never stored. This
/// is a small, standalone registry just for that: one row per MIDI device ever assigned an icon,
/// matched the same best-effort way `InstrumentIdentityHint.midiPort` already matches for scene
/// reattachment — by `midiUniqueID` (CoreMIDI's own persistent per-device id) when available,
/// falling back to `displayName` otherwise (a device with no stable unique id, or a hint captured
/// before one was read).
@Model
final class MIDIDeviceIconRecord {
    var midiUniqueID: Int32?
    var displayName: String = ""
    var iconSystemName: String = ""

    init(midiUniqueID: Int32?, displayName: String, iconSystemName: String) {
        self.midiUniqueID = midiUniqueID
        self.displayName = displayName
        self.iconSystemName = iconSystemName
    }
}

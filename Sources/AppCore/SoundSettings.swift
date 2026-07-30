import Foundation
import SoundFontModel
import SwiftData

/// One sound's user-assigned metadata: an optional friendlier alias (decompressed sound
/// libraries often have cryptic/technical .sf2 filenames) and whether it's a favorite.
/// `soundFontHash` identifies the `.sf2`/`.dls` file itself by content hash (see
/// `SoundFontEntry.hash`) rather than by path — a soundfont can be freely renamed/moved by the
/// user in Finder/Files, which used to silently orphan a favorite/alias keyed by path (see
/// `ImprovSession.migrateSoundEntriesToHashKeyedIfNeeded`, the one-time bridge from the old
/// path-keyed shape).
///
/// `preset` distinguishes *which* preset within the soundfont this entry describes, for a
/// multi-preset `.sf2` file (see `SoundFontPresetReader`) — `nil` means "the file's own default
/// sound." Two entries can legitimately share the same `soundFontHash` as long as their `preset`
/// differs.
///
/// Only sounds the user has actually touched (given an alias, or favorited) get an entry.
public struct SoundEntry: Codable, Equatable, Sendable {
    public var soundFontHash: String
    public var alias: String?
    public var isFavorite: Bool
    public var preset: SoundFontPresetIdentity?
    /// An SF Symbol name (see `IconVocabulary`), suggested by the active LLM connection or
    /// picked manually — same optional, purely-decorative metadata as `alias`.
    public var iconSystemName: String?

    public init(soundFontHash: String, alias: String? = nil, isFavorite: Bool = false, preset: SoundFontPresetIdentity? = nil, iconSystemName: String? = nil) {
        self.soundFontHash = soundFontHash
        self.alias = alias
        self.isFavorite = isFavorite
        self.preset = preset
        self.iconSystemName = iconSystemName
    }
}

/// The on-disk shape of the OLD `sound-settings.json` (path-keyed) — kept only so
/// `ImprovSession.migrateSoundSettingsFromJSONIfNeeded` can still read a pre-existing file from
/// before the hash migration; never written anymore.
struct LegacySoundEntry: Codable {
    var path: String
    var alias: String?
    var isFavorite: Bool
    var preset: SoundFontPresetIdentity?
    var iconSystemName: String?
}

struct SoundSettingsFile: Codable {
    var sounds: [LegacySoundEntry]
}

/// The SwiftData-backed counterpart of `SoundEntry` — see `ColorPaletteRecord`'s doc comment
/// for the split rationale shared by every settings record in this migration wave.
/// `SoundFontPresetIdentity` (program/bank) is flattened into two optional `Int` fields rather
/// than stored as a nested Codable attribute, mirroring the "flatten to primitives" convention
/// used for `Scene`'s `InstrumentIdentityHint` elsewhere in this migration.
@Model
final class SoundEntryRecord {
    var soundFontHash: String = ""
    /// The OLD path-keyed identity, kept only for `migrateSoundEntriesToHashKeyedIfNeeded` to
    /// read once — never written or read afterward. `nil` for any entry created after that
    /// migration ran (i.e. every entry going forward).
    var legacyPath: String?
    var alias: String?
    var isFavorite: Bool = false
    var presetProgram: Int?
    var presetBank: Int?
    var iconSystemName: String?

    init(_ entry: SoundEntry) {
        soundFontHash = entry.soundFontHash
        alias = entry.alias
        isFavorite = entry.isFavorite
        presetProgram = entry.preset.map { Int($0.program) }
        presetBank = entry.preset.map { Int($0.bank) }
        iconSystemName = entry.iconSystemName
    }

    var asSoundEntry: SoundEntry {
        let preset: SoundFontPresetIdentity? = {
            guard let presetProgram, let presetBank else { return nil }
            return SoundFontPresetIdentity(program: UInt16(presetProgram), bank: UInt16(presetBank))
        }()
        return SoundEntry(soundFontHash: soundFontHash, alias: alias, isFavorite: isFavorite, preset: preset, iconSystemName: iconSystemName)
    }
}

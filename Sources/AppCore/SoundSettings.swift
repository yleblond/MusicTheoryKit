import Foundation
import SoundFontModel
import SwiftData

/// One sound's user-assigned metadata: an optional friendlier alias (decompressed sound
/// libraries often have cryptic/technical .sf2 filenames) and whether it's a favorite. `path`
/// is the same relative-path string `ImprovSession.sampleFiles` uses (relative to
/// `sampleFolder`, may include subfolders) — that's a sound file's real identity, not a bare
/// filename, since two different subfolders can contain a same-named file.
///
/// `preset` distinguishes *which* preset within `path` this entry describes, for a multi-preset
/// `.sf2` file (see `SoundFontPresetReader`) — `nil` means "the file's own default sound," the
/// only case that existed before multi-preset support, and still what every pre-existing
/// `sound-settings.json` entry decodes as. Two entries can legitimately share the same `path` as
/// long as their `preset` differs.
///
/// Only sounds the user has actually touched (given an alias, or favorited) get an entry —
/// `sound-settings.json` stays small and readable even when `sampleFolder` holds a huge
/// decompressed library with hundreds of files nobody has curated yet.
public struct SoundEntry: Codable, Equatable, Sendable {
    public var path: String
    public var alias: String?
    public var isFavorite: Bool
    public var preset: SoundFontPresetIdentity?
    /// An SF Symbol name (see `IconVocabulary`), suggested by the active LLM connection or
    /// picked manually — same optional, purely-decorative metadata as `alias`.
    public var iconSystemName: String?

    public init(path: String, alias: String? = nil, isFavorite: Bool = false, preset: SoundFontPresetIdentity? = nil, iconSystemName: String? = nil) {
        self.path = path
        self.alias = alias
        self.isFavorite = isFavorite
        self.preset = preset
        self.iconSystemName = iconSystemName
    }
}

/// The on-disk shape of `sound-settings.json` — a flat list under one key, same convention as
/// `ColorPaletteFile`/`palettes.json`.
struct SoundSettingsFile: Codable {
    var sounds: [SoundEntry]
}

/// The SwiftData-backed counterpart of `SoundEntry` — see `ColorPaletteRecord`'s doc comment
/// for the split rationale shared by every settings record in this migration wave.
/// `SoundFontPresetIdentity` (program/bank) is flattened into two optional `Int` fields rather
/// than stored as a nested Codable attribute, mirroring the "flatten to primitives" convention
/// used for `Scene`'s `InstrumentIdentityHint` elsewhere in this migration.
@Model
final class SoundEntryRecord {
    var path: String = ""
    var alias: String?
    var isFavorite: Bool = false
    var presetProgram: Int?
    var presetBank: Int?
    var iconSystemName: String?

    init(_ entry: SoundEntry) {
        path = entry.path
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
        return SoundEntry(path: path, alias: alias, isFavorite: isFavorite, preset: preset, iconSystemName: iconSystemName)
    }
}

import Foundation

/// One soundfont file known to the app, indexed by content hash rather than by path or
/// filename — a `.sf2`/`.dls` can be freely renamed or moved by the user in Finder/Files at any
/// time (unlike every other on-disk asset this app manages), so `hash` is the only identity
/// that survives that. `presets` is parsed once, at import/discovery time (see
/// `SoundFontPresetReader`), and never re-parsed afterward — this lets a device show a
/// soundfont's full preset list even when its file isn't downloaded locally yet.
public struct SoundFontEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String { hash }

    /// SHA-256 hex digest of the file's full byte content — see `SoundFontHasher`.
    public var hash: String
    /// User-editable display name — same "cryptic filename, friendlier name" role as
    /// `SoundEntry.alias` plays for an individual preset.
    public var displayName: String
    /// The file's current name on disk (informational — never part of this entry's identity).
    public var fileName: String
    public var fileSize: Int64
    public var presets: [SoundFontPreset]
    public var dateAdded: Date
    public var userTags: [String]
    public var origin: SoundFontOrigin
    /// Where this soundfont's bytes should live — the app's own choice of physical location
    /// (iCloud Drive container vs local-only `Application Support`), not whether it's actually
    /// downloaded on any particular device right now (see `SoundFontStorage`'s per-device
    /// download policy for that separate question).
    public var syncPreference: SoundFontSyncPreference

    public init(
        hash: String, displayName: String, fileName: String, fileSize: Int64,
        presets: [SoundFontPreset], dateAdded: Date, userTags: [String] = [],
        origin: SoundFontOrigin = .userImported, syncPreference: SoundFontSyncPreference = .localOnly
    ) {
        self.hash = hash
        self.displayName = displayName
        self.fileName = fileName
        self.fileSize = fileSize
        self.presets = presets
        self.dateAdded = dateAdded
        self.userTags = userTags
        self.origin = origin
        self.syncPreference = syncPreference
    }
}

/// Where a `SoundFontEntry` came from — a curated soundfont is otherwise a perfectly ordinary
/// imported one (same file layout, same import code path via `SoundFontLibrary.importFile`);
/// what's worth remembering is where to re-download it from if the local file ever disappears,
/// and which catalog entry/version it was installed from, so a later catalog update (a new app
/// release changing `version` for the same `catalogEntryId`) can be surfaced as "update
/// available" instead of silently going unnoticed (see `CuratedSoundFontCatalog`).
public enum SoundFontOrigin: Codable, Equatable, Sendable {
    case userImported
    case curated(sourceURL: URL, catalogEntryId: String, catalogVersion: String)
}

/// Physical placement choice for a soundfont's bytes — `synced` means "lives in the app's
/// iCloud Drive container" (visible/rapatriable on every device signed into the same account),
/// `localOnly` means "lives only in this device's own `Application Support`, never shows up
/// anywhere else." See `KnowledgeBase/SoundfontMgt/soundfontmgt.txt` for the full rationale
/// (iCloud quota is the user's, not free to spend by default).
public enum SoundFontSyncPreference: String, Codable, Equatable, Sendable {
    case synced
    case localOnly
}

/// `SoundFontPreset` (declared in `SoundFontPresetReader.swift`) needs no changes to its own
/// parsing logic — this conformance only lets it round-trip through `SoundFontEntry`/
/// `SoundFontRecord`'s JSON encoding, added here rather than in the parser file to keep that
/// file scoped to RIFF parsing alone.
extension SoundFontPreset: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, program, bank
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            program: try container.decode(UInt16.self, forKey: .program),
            bank: try container.decode(UInt16.self, forKey: .bank)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(program, forKey: .program)
        try container.encode(bank, forKey: .bank)
    }
}

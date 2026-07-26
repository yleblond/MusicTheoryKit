import Foundation

/// One sound file's user-assigned metadata: an optional friendlier alias (decompressed sound
/// libraries often have cryptic/technical .sf2 filenames) and whether it's a favorite. `path`
/// is the same relative-path string `ImprovSession.sampleFiles` uses (relative to
/// `sampleFolder`, may include subfolders) — that's a sound file's real identity, not a bare
/// filename, since two different subfolders can contain a same-named file.
///
/// Only sounds the user has actually touched (given an alias, or favorited) get an entry —
/// `sound-settings.json` stays small and readable even when `sampleFolder` holds a huge
/// decompressed library with hundreds of files nobody has curated yet.
public struct SoundEntry: Codable, Equatable, Sendable {
    public var path: String
    public var alias: String?
    public var isFavorite: Bool

    public init(path: String, alias: String? = nil, isFavorite: Bool = false) {
        self.path = path
        self.alias = alias
        self.isFavorite = isFavorite
    }
}

/// The on-disk shape of `sound-settings.json` — a flat list under one key, same convention as
/// `ColorPaletteFile`/`palettes.json`.
struct SoundSettingsFile: Codable {
    var sounds: [SoundEntry]
}

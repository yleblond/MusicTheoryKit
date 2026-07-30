import Foundation
import SwiftData

/// The SwiftData-backed counterpart of `SoundFontEntry` — same split as `ColorPaletteRecord`/
/// `ColorPalette` in `AppCore`. `presets` is encoded as one JSON blob (`encodedPresets`) rather
/// than a relationship, mirroring `SceneRecord`'s reasoning for `encodedScene`: this shared
/// schema (see `ImprovSession.modelContainer`) stays CloudKit-compatible only because every
/// record avoids relationships and unique constraints, so a `[SoundFontPreset]` column would
/// need the same flattening `SceneRecord` already does for `InstrumentIdentityHint` — a blob is
/// simpler here since presets are never queried individually, only read as a whole list.
///
/// `contentHash` is a logical key, not a SwiftData/CloudKit unique constraint (none are allowed
/// in this schema) — callers look records up with
/// `#Predicate<SoundFontRecord> { $0.contentHash == hash }`, same convention as every other
/// string-keyed lookup in this migration wave. Deliberately NOT named `hash`: `@Model` classes
/// are backed by Core Data's `NSManagedObject`, which (like every `NSObject`) already declares
/// its own `@objc var hash: UInt` for `-isEqual:`/hashing purposes — a stored property of the
/// same name collided with it in practice (confirmed: crashed inside SwiftData/Core Data with
/// "Could not cast NSCFNumber to NSString" the moment a record was inserted, `NSObject`'s own
/// integer `hash` colliding with this `String` one) — never reuse this name on a `@Model` type.
@Model
public final class SoundFontRecord {
    public var contentHash: String = ""
    public var displayName: String = ""
    public var fileName: String = ""
    public var fileSize: Int64 = 0
    public var encodedPresets: Data = Data()
    public var dateAdded: Date = Date()
    public var userTags: [String] = []
    /// "userImported" | "curated" — flattened `SoundFontOrigin`, same "raw string tag + optional
    /// side field" pattern as `MIDIDeviceIconRecord`'s own fallback fields.
    public var originKind: String = "userImported"
    public var curatedSourceURLString: String?
    /// Raw `SoundFontSyncPreference` value ("synced" | "localOnly").
    public var syncPreference: String = "localOnly"

    public init(_ entry: SoundFontEntry) {
        contentHash = entry.hash
        displayName = entry.displayName
        fileName = entry.fileName
        fileSize = entry.fileSize
        encodedPresets = (try? JSONEncoder().encode(entry.presets)) ?? Data()
        dateAdded = entry.dateAdded
        userTags = entry.userTags
        switch entry.origin {
        case .userImported:
            originKind = "userImported"
            curatedSourceURLString = nil
        case .curated(let sourceURL):
            originKind = "curated"
            curatedSourceURLString = sourceURL.absoluteString
        }
        syncPreference = entry.syncPreference.rawValue
    }

    /// `nil` only if `encodedPresets` somehow fails to decode (should never happen for a row
    /// this type itself wrote) — callers already treat every SwiftData record this way
    /// (`SceneRecord.asScene`, etc.).
    public var asSoundFontEntry: SoundFontEntry? {
        guard let presets = try? JSONDecoder().decode([SoundFontPreset].self, from: encodedPresets) else { return nil }
        let origin: SoundFontOrigin
        if originKind == "curated", let urlString = curatedSourceURLString, let url = URL(string: urlString) {
            origin = .curated(sourceURL: url)
        } else {
            origin = .userImported
        }
        return SoundFontEntry(
            hash: contentHash, displayName: displayName, fileName: fileName, fileSize: fileSize,
            presets: presets, dateAdded: dateAdded, userTags: userTags, origin: origin,
            syncPreference: SoundFontSyncPreference(rawValue: syncPreference) ?? .localOnly
        )
    }

    /// Applies every mutable field of `entry` onto this existing record — used by upsert paths
    /// (`SoundFontLibrary.importFile`/reconciliation) that look up an existing row by `hash`
    /// rather than always inserting a fresh one.
    public func update(from entry: SoundFontEntry) {
        displayName = entry.displayName
        fileName = entry.fileName
        fileSize = entry.fileSize
        encodedPresets = (try? JSONEncoder().encode(entry.presets)) ?? encodedPresets
        userTags = entry.userTags
        switch entry.origin {
        case .userImported:
            originKind = "userImported"
            curatedSourceURLString = nil
        case .curated(let sourceURL):
            originKind = "curated"
            curatedSourceURLString = sourceURL.absoluteString
        }
        syncPreference = entry.syncPreference.rawValue
    }
}

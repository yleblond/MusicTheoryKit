import Foundation
import SwiftData

/// A single, CloudKit-synced value: the user's own self-imposed "budget" for how much iCloud
/// storage their synced soundfonts should occupy — purely a display aid for `StorageUsageBar`
/// (shows where this budget falls on the usage bar), never enforced (nothing stops importing
/// past it). Synced — unlike `LocalStorageThreshold`, deliberately NOT per-device — because
/// iCloud storage itself is account-wide, not per-device: the same number means the same thing
/// on every device signed into the account.
///
/// Singleton by convention only, same as `LumiSettingsRecord`/every other single-value settings
/// record in this app: no unique constraint (none are allowed in this CloudKit-backed schema —
/// see `ImprovSession.modelContainer`'s own doc comment), every read/write just treats the
/// first fetched row as the only one.
@Model
public final class CloudStorageThresholdRecord {
    public var bytes: Int64?

    public init(bytes: Int64?) {
        self.bytes = bytes
    }
}

import Foundation

/// A user-set local disk-space budget for soundfonts on THIS device — purely a display aid for
/// `StorageUsageBar` (shows "free up to my own limit" instead of "free on the whole volume"),
/// never enforced anywhere (nothing stops an import or a sync-preference change past it).
/// Per-device, deliberately in plain `UserDefaults` (never synced) — same rationale as
/// `DeviceStorageProfile`: a Mac with 2 TB free and an iPhone with 30 GB free legitimately want
/// different limits for the exact same synced library.
public enum LocalStorageThreshold {
    private static let key = "JamShackLocalStorageThresholdBytes"
    private static let hasBeenSetKey = "JamShackLocalStorageThresholdBytesHasBeenSet"
    /// First-launch default, per explicit user request — distinct from a later explicit clear
    /// back to "no limit" (tracked separately via `hasBeenSetKey`, so clearing doesn't just
    /// silently reappear as 1 GB on the next read).
    private static let defaultBytes: Int64 = 1_000_000_000

    /// `nil` means "no limit set" — callers should fall back to the device's real free space
    /// in that case (see `StorageSegment.build`). Reports the 1 GB default on first launch
    /// (before the user has ever touched this setting on this device), `nil` if they've since
    /// explicitly cleared it.
    public static var bytes: Int64? {
        get {
            if let stored = (UserDefaults.standard.object(forKey: key) as? NSNumber)?.int64Value {
                return stored
            }
            return UserDefaults.standard.bool(forKey: hasBeenSetKey) ? nil : defaultBytes
        }
        set {
            UserDefaults.standard.set(true, forKey: hasBeenSetKey)
            if let newValue {
                UserDefaults.standard.set(NSNumber(value: newValue), forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}

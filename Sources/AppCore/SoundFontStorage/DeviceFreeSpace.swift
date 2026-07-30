import Foundation

/// Local disk free-space measurement — the one storage-capacity signal this app CAN measure
/// directly and reliably (unlike remaining iCloud account quota, which no public API exposes —
/// see `DeviceStorageProfile`'s own doc comment). Queried against the volume hosting
/// `Application Support` (where local-only, and downloaded-synced, soundfonts actually live),
/// since that's the volume any local download consumes space on.
public enum DeviceFreeSpace {
    public static func availableBytes() -> Int64 {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // "ImportantUsage" (not "OpportunisticUsage"/plain `.volumeAvailableCapacityKey`) is the
        // right key for "the user explicitly wants this file now" — matches how a soundfont
        // download is actually requested, as opposed to speculative/cache-style prefetching.
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

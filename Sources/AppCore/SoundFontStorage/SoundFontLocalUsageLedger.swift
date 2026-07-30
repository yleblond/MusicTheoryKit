import Foundation

/// Tracks which soundfonts were actually played on THIS device recently — a signal used only to
/// bias `SoundFontDownloadPolicy` toward downloading something the user demonstrably still
/// cares about, even past the size/space thresholds that would otherwise skip it. Deliberately
/// NOT synced (plain `UserDefaults`, same convention as
/// `DeviceStorageProfile`): playing a soundfont on the Mac must never force its download on the
/// iPhone too — each device judges "recently used" only by its own history.
public enum SoundFontLocalUsageLedger {
    private static let userDefaultsKey = "JamShackSoundFontLocalUsageLedger"
    public static let defaultWindow: TimeInterval = 30 * 24 * 3600

    public static func recordUse(_ hash: String, at date: Date = Date()) {
        var entries = readAll()
        entries[hash] = date
        persist(entries)
    }

    public static func wasUsedRecently(_ hash: String, within window: TimeInterval = defaultWindow, now: Date = Date()) -> Bool {
        guard let date = readAll()[hash] else { return false }
        return now.timeIntervalSince(date) <= window
    }

    private static func readAll() -> [String: Date] {
        let raw = (UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Double]) ?? [:]
        return raw.mapValues { Date(timeIntervalSinceReferenceDate: $0) }
    }

    private static func persist(_ entries: [String: Date]) {
        UserDefaults.standard.set(entries.mapValues { $0.timeIntervalSinceReferenceDate }, forKey: userDefaultsKey)
    }
}

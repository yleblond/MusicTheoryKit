import Foundation

#if os(iOS)
import UIKit
#endif

/// How willing THIS device is to spend local disk space downloading synced soundfonts —
/// compensates for the one thing this app genuinely can't measure: Apple exposes no public API
/// for a third-party app to read a signed-in iCloud account's total or remaining storage quota
/// (only this device's own local free space is directly measurable — see `DeviceFreeSpace`).
/// A user with a generous paid iCloud plan sets this once per device; there is no way to infer
/// that from anything the app can observe, so this is deliberately a user-visible setting, not
/// a heuristic dressed up as one.
public enum DeviceStorageProfile: String, Codable, CaseIterable, Sendable {
    case economical
    case standard
    case generous

    private static let userDefaultsKey = "JamShackSoundFontStorageProfile"

    /// Per-device, deliberately in plain `UserDefaults` rather than the shared CloudKit store —
    /// same "not everything should sync" precedent as `DefaultFolderBookmark`
    /// (`App/Sources/DefaultFolders.swift`): the whole point is that a Mac with 2 TB free and
    /// an iPhone with 30 GB free can legitimately want different answers for the exact same
    /// synced soundfont library.
    public static var current: DeviceStorageProfile {
        get {
            if let raw = UserDefaults.standard.string(forKey: userDefaultsKey), let value = DeviceStorageProfile(rawValue: raw) {
                return value
            }
            return defaultForThisDevice
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey) }
    }

    /// First-launch default, before the user has ever touched the setting — based only on the
    /// device's own idiom (never a guess at the iCloud account itself, which isn't
    /// observable). iPad and Mac both default to `.standard`: only a phone's typically much
    /// smaller local storage warrants starting conservative.
    private static var defaultForThisDevice: DeviceStorageProfile {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone ? .economical : .standard
        #else
        return .standard
        #endif
    }
}

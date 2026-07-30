import Foundation

public enum SoundFontLocationsError: Error, Equatable {
    /// No iCloud account signed in, or this build isn't signed with the ubiquity-container
    /// capability (e.g. an ad-hoc "Sign to Run Locally" build) — same class of failure the
    /// CloudKit-backed `modelContainer` already falls back gracefully from (see
    /// `ImprovSession.modelContainer`'s own doc comment).
    case iCloudContainerUnavailable
}

/// Resolves the two physical folders a soundfont's bytes can live in — replaces the old
/// `DefaultFolderBookmark`/`FolderPickerRow` flow (a security-scoped bookmark to a folder the
/// USER picks) for soundfonts specifically: both folders here are the app's own, discovered
/// automatically, never chosen by hand. See `KnowledgeBase/SoundfontMgt/soundfontmgt.txt`.
public enum SoundFontLocations {
    /// Same identifier as the CloudKit database container (`ImprovSession.modelContainer`) —
    /// one container serves both the lightweight CloudKit index AND the actual iCloud Drive
    /// file bytes, per `App/project.yml`'s `com.apple.developer.ubiquity-container-identifiers`.
    private static let ubiquityContainerIdentifier = "iCloud.com.jamshack.JamShackApp"
    private static let subfolderName = "SoundFonts"

    /// The app's iCloud Drive container, visible to the user in Files/Finder as "JamShack" (see
    /// `NSUbiquitousContainers` in `App/project.yml`). `FileManager.url(forUbiquityContainerIdentifier:)`
    /// is documented as potentially slow on first call — acceptable here since it's only ever
    /// invoked once, synchronously, during the same app-launch sequence that already does
    /// several other blocking migrations (see `configureDefaultFolders`).
    public static func syncedFolderURL() throws -> URL {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: ubiquityContainerIdentifier) else {
            throw SoundFontLocationsError.iCloudContainerUnavailable
        }
        let folder = container.appendingPathComponent("Documents").appendingPathComponent(subfolderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Never depends on iCloud — always available, even with no account signed in. Never shown
    /// to the user directly (unlike the synced folder, which is a normal Files/Finder location).
    public static func localFolderURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent(subfolderName)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// `nil` means "iCloud unavailable on this device right now" — every caller should treat
    /// that as "act as if every soundfont were local-only," never as an error to surface.
    public static func syncedFolderURLIfAvailable() -> URL? {
        try? syncedFolderURL()
    }

    /// Whether an iCloud account is signed in for this app at all (independent of whether the
    /// ubiquity container itself is currently reachable) — mirrors the check
    /// `ImprovSession.modelContainer` already relies on implicitly via its own CloudKit fallback.
    public static var isICloudAccountAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}

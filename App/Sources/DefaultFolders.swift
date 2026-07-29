import Foundation
import AppCore

/// Persists ONE security-scoped bookmark — the "JamShack" root folder, wherever the user put
/// it (by default, iCloud Drive/JamShack) — across app launches, so the sandboxed folder
/// access `FolderPickerRow` documents as "only lasts while the app runs" doesn't have to be
/// redone by hand every single time for this, the common case. Deliberately ONE bookmark for
/// a whole root, not six (one per subfolder) — simpler, and matches how the CLI's own default
/// setup (`Sources/JamShack/main.swift`) always moves `User`/`Library` together as fixed
/// children of one root, never independently.
enum DefaultFolderBookmark {
    private static let key = "JamShackDefaultRootFolderBookmark"

    static func save(_ url: URL) {
        guard let data = try? url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Resolves the saved bookmark and starts security-scoped access for it — the caller is
    /// responsible for keeping that access alive for as long as it's needed (same
    /// "app-lifetime, never explicitly stopped" convention already used for a folder picked
    /// via `FolderPickerRow`). `nil` if nothing was ever saved, or the saved location can no
    /// longer be resolved/accessed (e.g. iCloud Drive not signed in on this device) — the
    /// caller should just fall back to the per-category manual pickers in that case.
    static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: resolutionOptions, relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        if isStale { save(url) }
        return url
    }

    #if os(macOS)
    private static let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    private static let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    private static let bookmarkOptions: URL.BookmarkCreationOptions = []
    private static let resolutionOptions: URL.BookmarkResolutionOptions = []
    #endif
}

/// The 6 subfolder names the CLI's own default setup creates under `User`/`Library`
/// (`Sources/JamShack/main.swift`) — flattened here as direct children of ONE root instead of
/// split across those two, since this app has no equivalent "run from a repo checkout"
/// concept to hang that split off of. Suggested root: iCloud Drive/JamShack, so a user's
/// pieces/scenes/sounds/etc. sync across their own devices, but any folder works the same way.
func configureDefaultFolders(in root: URL, session: ImprovSession) {
    let fileManager = FileManager.default
    func ensure(_ name: String) -> URL {
        let folder = root.appendingPathComponent(name)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    session.migratePiecesFromJSONIfNeeded(in: ensure("Pieces").path)
    try? session.listSampleFiles(in: ensure("SoundFonts").path)
    session.migrateSoundTracksFromJSONIfNeeded(in: ensure("SoundTracks").path)
    session.migrateGuideSequencesFromJSONIfNeeded(in: ensure("Sequences").path)
    session.ensureGuideReadyForLaunch()
    session.migrateScenesFromJSONIfNeeded(in: ensure("Scenes").path)
    session.ensureSceneReadyForLaunch()
    try? session.setPromptsFolder(ensure("Composition IA").path)
    // Also creates/loads `Settings/LLMConnections/` (LLM connection descriptors),
    // `Settings/palettes.json`, `chordprogressions.json`, `language.json`, `lumi.json`,
    // `note-colors.json` and `llm-api-keys.json` — one call, see `setSettingsFolder`'s own
    // doc comment for why these all move together. Previously never auto-configured in this
    // app (unlike the CLI's own startup, `Sources/JamShack/main.swift`), so a fresh install
    // required navigating to JamShack > Dossiers > Reglages by hand before any LLM
    // connection could be listed at all.
    try? session.setSettingsFolder(ensure("Settings").path)
}

#if os(macOS)
/// `~/Library/Mobile Documents/com~apple~CloudDocs` — where macOS mounts iCloud Drive for the
/// signed-in account, regardless of whether THIS app has any iCloud entitlement of its own: an
/// `NSOpenPanel` (unlike the sandboxed app itself) can always browse the whole filesystem, so
/// pointing it here just saves the user a few clicks of manual navigation. `nil` if iCloud
/// Drive isn't actually set up on this Mac (falls back to the panel's own default location).
/// macOS-only: `homeDirectoryForCurrentUser` is unavailable on iOS (no equivalent concept in a
/// sandboxed app there) — iOS instead relies on `.fileImporter`'s own document picker, which
/// already surfaces "iCloud Drive" as a browsable location without needing a path hint.
func iCloudDriveURLIfAvailable() -> URL? {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}
#endif

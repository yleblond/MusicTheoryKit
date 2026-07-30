import Foundation
import SoundFontModel
import SwiftData

/// Owns soundfont discovery/reconciliation for one `ImprovSession`: an `NSMetadataQuery`
/// watching the synced (iCloud Drive) folder so a file dropped/renamed/removed directly in
/// Files/Finder is picked up without any explicit import call, a plain one-time directory scan
/// for the local-only folder (nobody but this app ever touches that folder, so it needs no live
/// watcher — see `reconcileLocalFolderOnce`), and the upsert into `SoundFontRecord` that keeps
/// the SwiftData index in sync with whatever is actually on disk. See
/// `KnowledgeBase/SoundfontMgt/soundfontmgt.txt` for why the index (hash/presets/tags) and the
/// actual bytes live in two different sync mechanisms (CloudKit vs iCloud Drive).
///
// `@unchecked Sendable`: same rationale as `ImprovSession` itself — the `NSMetadataQuery`
// notification handlers hop to the main thread before touching `modelContext` (thread-confined
// to wherever it was created, same contract as `ImprovSession.modelContext`), so this is never
// truly concurrent despite callbacks arriving from a background operation queue.
public final class SoundFontLibrary: @unchecked Sendable {
    private let modelContext: ModelContext
    private var metadataQuery: NSMetadataQuery?
    /// The folder passed to `start(syncedFolder:localFolder:onChange:)` — exposed read-only so
    /// callers that need to know it (e.g. `ImprovSession.migrateSoundFontsFromFolderScanIfNeeded`,
    /// deciding whether an old file already sits under it) don't have to re-resolve
    /// `SoundFontLocations` a second time themselves (wasteful, and — for `syncedFolderURL()` —
    /// not side-effect-free).
    public private(set) var syncedFolder: URL?
    /// Same rationale as `syncedFolder` above — exposed so `ImprovSession.soundFontPath(forHash:)`
    /// resolves against the folder THIS library actually started with (real in production,
    /// an isolated temp directory in tests), never a second independent call to
    /// `SoundFontLocations.localFolderURL()`.
    public private(set) var localFolder: URL?
    private var onChange: (() -> Void)?
    private var notificationObservers: [NSObjectProtocol] = []
    /// Consecutive reconcile passes a known (by hash) synced soundfont has been absent from
    /// `NSMetadataQuery`'s results — a single miss is deleted only after being confirmed twice,
    /// a cheap guard against pruning an entry from a transient/mid-gather query snapshot (the
    /// plain local-folder scan never needs this: `contentsOfDirectory` is always a complete,
    /// consistent listing, so a miss there is deleted immediately).
    private var missingSyncedStreak: [String: Int] = [:]

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    deinit { stop() }

    /// Starts watching both folders and does one immediate local-folder reconciliation.
    /// `syncedFolder` is `nil` when iCloud isn't available right now (see
    /// `SoundFontLocations.syncedFolderURLIfAvailable`) — everything then behaves as local-only,
    /// same graceful-degradation contract as the rest of this app's iCloud-dependent features.
    public func start(syncedFolder: URL?, localFolder: URL, onChange: @escaping () -> Void) {
        stop()
        self.syncedFolder = syncedFolder
        self.localFolder = localFolder
        self.onChange = onChange

        reconcileLocalFolderOnce(localFolder)

        guard let syncedFolder else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [syncedFolder]
        query.predicate = NSPredicate(format: "%K LIKE '*.sf2' OR %K LIKE '*.dls'", NSMetadataItemFSNameKey, NSMetadataItemFSNameKey)
        // A dedicated queue, not `.main`: gathering a large synced library shouldn't ever block
        // UI. The notification handlers themselves hop back to the main thread before touching
        // `modelContext` (thread-confined — see this type's own doc comment), same pattern
        // `ImprovSession.startObservingRemoteStoreChanges` already uses for CloudKit's own
        // remote-change notifications.
        query.operationQueue = OperationQueue()

        // Reads back `self.metadataQuery` rather than capturing `query` directly — sidesteps
        // sending a non-`Sendable` `NSMetadataQuery` across the actor boundary in this
        // `@escaping` closure; `metadataQuery` is set right below, before `query.start()` can
        // possibly fire either notification.
        let center = NotificationCenter.default
        notificationObservers = [
            center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: nil) { [weak self] _ in
                self?.handleMetadataQueryNotification()
            },
            center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: nil) { [weak self] _ in
                self?.handleMetadataQueryNotification()
            },
        ]
        metadataQuery = query
        query.start()
    }

    private func handleMetadataQueryNotification() {
        guard let metadataQuery else { return }
        handleQueryUpdate(metadataQuery)
    }

    public func stop() {
        metadataQuery?.stop()
        metadataQuery = nil
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers = []
    }

    /// Requests that a `.synced` soundfont's bytes actually be downloaded to this device — a
    /// no-op if it's already local, or if it isn't `.synced` at all (nothing to download).
    /// `NSMetadataQuery`'s own next update will report the new downloaded status; there's no
    /// synchronous "done" signal from this call.
    public func requestDownload(of entry: SoundFontEntry) throws {
        guard entry.syncPreference == .synced, let syncedFolder else { return }
        let url = syncedFolder.appendingPathComponent(entry.fileName)
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    /// Parses presets (`SoundFontPresetReader`, unmodified), copies+hashes into the chosen
    /// destination folder (never a security-scoped bookmark — a plain owned copy, so the
    /// original file can be renamed/moved/deleted by the user afterward with no effect), then
    /// upserts the index. `destination` silently falls back to `.localOnly` if `.synced` was
    /// requested but iCloud isn't actually available right now — never a hard failure. Preset
    /// parsing failure is NOT fatal here either — a `.dls` (a different RIFF form entirely, no
    /// `phdr` chunk to find) or a corrupt `.sf2` still imports and indexes fine, just with an
    /// empty preset list, same tolerance `SoundFontPresetReader`'s other callers already show.
    @discardableResult
    public func importFile(
        at source: URL, destination: SoundFontSyncPreference,
        displayName: String? = nil, origin: SoundFontOrigin = .userImported
    ) throws -> SoundFontEntry {
        let presets = (try? SoundFontPresetReader.presets(at: source)) ?? []
        let effectiveDestination: SoundFontSyncPreference = (destination == .synced && syncedFolder == nil) ? .localOnly : destination
        guard let folder = effectiveDestination == .synced ? syncedFolder : localFolder else {
            throw SoundFontLocationsError.iCloudContainerUnavailable
        }
        let destinationURL = uniqueDestinationURL(in: folder, preferredName: source.lastPathComponent)
        let hash = try SoundFontHasher.copyAndHash(from: source, to: destinationURL)
        let fileSize = fileSize(at: destinationURL)
        let entry = SoundFontEntry(
            hash: hash,
            displayName: displayName ?? source.deletingPathExtension().lastPathComponent,
            fileName: destinationURL.lastPathComponent,
            fileSize: fileSize,
            presets: presets,
            dateAdded: Date(),
            origin: origin,
            syncPreference: effectiveDestination
        )
        upsert(entry)
        return entry
    }

    // MARK: - Reconciliation

    private struct DiskItem {
        let url: URL
        let fileName: String
        let fileSize: Int64
    }

    private func handleQueryUpdate(_ query: NSMetadataQuery) {
        query.disableUpdates()
        let items: [DiskItem] = query.results.compactMap { result in
            guard let item = result as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { return nil }
            let size = (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value ?? 0
            return DiskItem(url: url, fileName: url.lastPathComponent, fileSize: size)
        }
        query.enableUpdates()
        DispatchQueue.main.async { [weak self] in
            self?.reconcile(items: items, syncPreference: .synced, requireConfirmedMiss: true)
        }
    }

    private func reconcileLocalFolderOnce(_ folder: URL) {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        let items: [DiskItem] = names.compactMap { name in
            let lowercased = name.lowercased()
            guard lowercased.hasSuffix(".sf2") || lowercased.hasSuffix(".dls") else { return nil }
            let url = folder.appendingPathComponent(name)
            return DiskItem(url: url, fileName: name, fileSize: fileSize(at: url))
        }
        reconcile(items: items, syncPreference: .localOnly, requireConfirmedMiss: false)
    }

    private func fileSize(at url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    /// Upserts every item currently on disk for `syncPreference`'s folder, then prunes index
    /// entries for that same folder whose file no longer appears — skipping re-hash for any
    /// item whose (fileName, fileSize) already matches a known record (a gigabyte-scale file
    /// should never be re-hashed on every launch/query update just to confirm nothing changed).
    /// `.curated` entries are never pruned even when their file is gone (they can be
    /// re-downloaded — see `CuratedSoundFontCatalog`).
    private func reconcile(items: [DiskItem], syncPreference: SoundFontSyncPreference, requireConfirmedMiss: Bool) {
        let existing = (try? modelContext.fetch(FetchDescriptor<SoundFontRecord>())) ?? []
        let existingForLocation = existing.filter { $0.syncPreference == syncPreference.rawValue }
        var seenHashes: Set<String> = []

        for item in items {
            if let match = existingForLocation.first(where: { $0.fileName == item.fileName && $0.fileSize == item.fileSize }) {
                seenHashes.insert(match.contentHash)
                missingSyncedStreak[match.contentHash] = nil
                continue
            }
            // Presets are best-effort (`.dls`/a corrupt `.sf2` just indexes with an empty
            // list — see `importFile`'s own doc comment); only a hashing failure (unreadable
            // file) is fatal enough to skip indexing entirely.
            guard let hash = try? SoundFontHasher.sha256Hex(ofFileAt: item.url) else { continue }
            let presets = (try? SoundFontPresetReader.presets(at: item.url)) ?? []
            seenHashes.insert(hash)
            missingSyncedStreak[hash] = nil
            if let record = existing.first(where: { $0.contentHash == hash }) {
                if var entry = record.asSoundFontEntry {
                    entry.fileName = item.fileName
                    entry.fileSize = item.fileSize
                    entry.syncPreference = syncPreference
                    record.update(from: entry)
                }
            } else {
                let entry = SoundFontEntry(
                    hash: hash, displayName: item.fileName, fileName: item.fileName, fileSize: item.fileSize,
                    presets: presets, dateAdded: Date(), syncPreference: syncPreference
                )
                modelContext.insert(SoundFontRecord(entry))
            }
        }

        for record in existingForLocation where !seenHashes.contains(record.contentHash) {
            if record.originKind == "curated" { continue }
            guard requireConfirmedMiss else {
                modelContext.delete(record)
                continue
            }
            let streak = (missingSyncedStreak[record.contentHash] ?? 0) + 1
            missingSyncedStreak[record.contentHash] = streak
            guard streak >= 2 else { continue }
            modelContext.delete(record)
            missingSyncedStreak[record.contentHash] = nil
        }

        try? modelContext.save()
        onChange?()
    }

    private func upsert(_ entry: SoundFontEntry) {
        let hash = entry.hash
        let descriptor = FetchDescriptor<SoundFontRecord>(predicate: #Predicate { $0.contentHash == hash })
        if let existingRecord = try? modelContext.fetch(descriptor).first {
            existingRecord.update(from: entry)
        } else {
            modelContext.insert(SoundFontRecord(entry))
        }
        try? modelContext.save()
        onChange?()
    }

    private func uniqueDestinationURL(in folder: URL, preferredName: String) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(preferredName)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let ext = (preferredName as NSString).pathExtension
        let base = (preferredName as NSString).deletingPathExtension
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }
}

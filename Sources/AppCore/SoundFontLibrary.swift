import Foundation
import SoundFontModel
import SwiftData

public enum SoundFontLibraryError: Error, Equatable, CustomStringConvertible {
    /// Raised by `changeSyncPreference` when the file isn't actually present on this device
    /// right now (a `.synced` entry not yet downloaded) — there's nothing to move.
    case notDownloadedOnThisDevice
    /// Raised when a hash no longer matches any record — the row was deleted (by another
    /// device, by reconciliation, or by the user) between the UI reading it and this call
    /// actually running. Previously mis-reported as `SoundFontLocationsError
    /// .iCloudContainerUnavailable`, which had nothing to do with iCloud and only confused
    /// what was actually a stale-row problem for a genuine iCloud-availability one.
    case recordNotFound

    public var description: String {
        switch self {
        case .notDownloadedOnThisDevice:
            return "this soundfont isn't downloaded on this device yet — download it first, then change where it lives"
        case .recordNotFound:
            return "this soundfont is no longer in the library (removed elsewhere) — refresh and try again"
        }
    }
}

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
    /// Wall-clock time a known (by hash) synced soundfont has been continuously absent from
    /// `NSMetadataQuery`'s results — pruned only once it's been missing for a real minimum
    /// duration (`missingGracePeriod`), NOT just some number of notification firings. This was
    /// originally a firing-count streak (confirm-after-2), which turned out to give close to NO
    /// real protection: `.NSMetadataQueryDidUpdate` can fire several times within milliseconds
    /// of each other (Spotlight-style metadata indexing lags behind the raw file actually
    /// existing on disk, especially right after a big change like moving a file INTO the synced
    /// folder), so 2 consecutive firings could — and did, confirmed the hard way — both land
    /// before the moved file was ever indexed, deleting a perfectly valid record within
    /// moments of `changeSyncPreference`/`importFile` placing it there. A real time budget is
    /// the only thing that actually waits for indexing to catch up. (The plain local-folder scan
    /// never needs this at all: `contentsOfDirectory` is always a complete, consistent listing,
    /// so a miss there is deleted immediately.)
    private var missingSince: [String: Date] = [:]
    private let missingGracePeriod: TimeInterval = 20

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Sets `syncedFolder`/`localFolder` directly, without running `start()`'s
    /// `deduplicate()`/`reconcileLocalFolderOnce`/`NSMetadataQuery` side effects — for tests that
    /// need to exercise `delete(hash:)`/`wipeEverything()` against a hand-built (including
    /// deliberately corrupted/duplicated) store, where those side effects would interfere with
    /// the very state the test is trying to set up.
    internal func setFoldersForTesting(syncedFolder: URL?, localFolder: URL) {
        self.syncedFolder = syncedFolder
        self.localFolder = localFolder
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

        // Before any reconciliation runs — a duplicate-hash group confuses reconciliation's own
        // per-location bookkeeping (each duplicate lives in a different `existingForLocation`
        // bucket), so cleaning up first means reconciliation never has to reason about
        // duplicates existing at all. See `deduplicate()`'s own doc comment for how these
        // duplicates arise in the first place (now fixed at the source too).
        deduplicate()
        reconcileLocalFolderOnce(localFolder)

        guard let syncedFolder else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [syncedFolder]
        // `LIKE` is case-sensitive by default — without `[c]`, a real file named e.g.
        // "MyBank.SF2" (common: many sample-library distributions use uppercase extensions)
        // would never appear in this query's results at all, silently, forever — which this
        // library's own "missing after a grace period" pruning would eventually (wrongly)
        // interpret as "the file was deleted" and remove its perfectly-valid record. Confirmed
        // as a real cause of soundfonts disappearing sometime after being marked synced.
        query.predicate = NSPredicate(format: "%K LIKE[c] '*.sf2' OR %K LIKE[c] '*.dls'", NSMetadataItemFSNameKey, NSMetadataItemFSNameKey)
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

    /// Deletes a soundfont's bytes (best-effort — a `.synced` entry not yet downloaded here has
    /// nothing local to remove, which is fine) and its index record. For a `.synced` entry this
    /// removes the file from the app's iCloud Drive container, i.e. from every device signed
    /// into the account — same semantics as deleting it in Files/Finder, not a per-device-only
    /// removal. Returns the first deleted entry (`nil` if `hash` wasn't known) so the caller can
    /// clean up anything that referenced it (favorites/aliases).
    ///
    /// Deletes EVERY record matching `hash`, not just the first — a real (now-fixed, see
    /// `ImprovSession.migrateSoundFontsFromFolderScanIfNeeded`'s own doc comment) bug could
    /// leave two devices each with their own duplicate row for the same content, one
    /// `.localOnly` and one `.synced`; deleting only one used to leave the other behind,
    /// silently reappearing right after what looked like a successful delete. Distinct
    /// (folder, fileName) pairs across the duplicates are each removed at most once.
    @discardableResult
    public func delete(hash: String) -> SoundFontEntry? {
        let descriptor = FetchDescriptor<SoundFontRecord>(predicate: #Predicate { $0.contentHash == hash })
        let records = (try? modelContext.fetch(descriptor)) ?? []
        guard !records.isEmpty else { return nil }
        var removedPaths: Set<String> = []
        var firstEntry: SoundFontEntry?
        for record in records {
            guard let entry = record.asSoundFontEntry else { continue }
            if firstEntry == nil { firstEntry = entry }
            let folder = entry.syncPreference == .synced ? syncedFolder : localFolder
            if let folder {
                let path = folder.appendingPathComponent(entry.fileName).path
                if removedPaths.insert(path).inserted {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
            modelContext.delete(record)
        }
        try? modelContext.save()
        onChange?()
        return firstEntry
    }

    /// One-time cleanup for records already corrupted by the duplicate-insert bug fixed in
    /// `ImprovSession.migrateSoundFontsFromFolderScanIfNeeded` — merges every group of records
    /// sharing the same `contentHash` down to one survivor. Call once per `start()`, before any
    /// reconciliation runs, so reconciliation never has to reason about duplicates at all.
    /// Survivor choice: prefer a record whose file is actually present on THIS device (over one
    /// that isn't), then prefer `.synced` (benefits every device) over `.localOnly`, then just
    /// keep whichever was found first. Favorites/aliases (`SoundEntryRecord`, keyed by hash, not
    /// by row) are unaffected either way — they keep working once the duplicate group is down
    /// to one row.
    public func deduplicate() {
        let all = (try? modelContext.fetch(FetchDescriptor<SoundFontRecord>())) ?? []
        let groupedByHash = Dictionary(grouping: all, by: \.contentHash)
        var didDelete = false
        for (_, group) in groupedByHash where group.count > 1 {
            let survivor = group.max { lhs, rhs in
                rank(of: lhs) < rank(of: rhs)
            }
            for record in group where record !== survivor {
                modelContext.delete(record)
                didDelete = true
            }
        }
        guard didDelete else { return }
        try? modelContext.save()
        onChange?()
    }

    /// Higher rank = kept over a lower-ranked duplicate — see `deduplicate()`'s own doc comment
    /// for the preference order this encodes.
    private func rank(of record: SoundFontRecord) -> Int {
        let isResident: Bool
        if let entry = record.asSoundFontEntry {
            let folder = entry.syncPreference == .synced ? syncedFolder : localFolder
            isResident = folder.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent(entry.fileName).path) } ?? false
        } else {
            isResident = false
        }
        if isResident { return 2 }
        return record.syncPreference == SoundFontSyncPreference.synced.rawValue ? 1 : 0
    }

    /// Wipes every known soundfont: every index record AND every `.sf2`/`.dls` file this device
    /// can see in both the local-only folder and the app's iCloud Drive container (the latter
    /// removes them from every device signed into the account, same as deleting them in
    /// Files/Finder). For recovering from exactly the kind of cross-device duplicate corruption
    /// `deduplicate()` cleans up gradually — a deliberate, explicit, user-requested nuke-and-pave
    /// rather than trying to reason about which of several conflicting rows is "correct."
    public func wipeEverything() {
        let all = (try? modelContext.fetch(FetchDescriptor<SoundFontRecord>())) ?? []
        for record in all {
            modelContext.delete(record)
        }
        for folder in [syncedFolder, localFolder].compactMap({ $0 }) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names {
                let lowercased = name.lowercased()
                guard lowercased.hasSuffix(".sf2") || lowercased.hasSuffix(".dls") else { continue }
                try? FileManager.default.removeItem(atPath: folder.appendingPathComponent(name).path)
            }
        }
        missingSince = [:]
        try? modelContext.save()
        onChange?()
    }

    /// Moves a soundfont's bytes between the synced (iCloud Drive) and local-only folders and
    /// updates its `syncPreference` — the "actually change it after import" counterpart to
    /// `importFile`'s own one-time choice. A no-op if `newPreference` already matches. Moving
    /// `.localOnly` → `.synced` puts the file in the app's iCloud Drive container, making it
    /// available on every device signed into the account; the reverse takes it out, so it
    /// exists only on this one device from then on — same semantics either way as physically
    /// dragging a file in/out of Files/Finder, since that IS what this does.
    /// Throws `SoundFontLibraryError.notDownloadedOnThisDevice` if the file isn't actually
    /// present here right now (a `.synced` entry not yet downloaded) — there's nothing to move;
    /// the caller should download it first (see `requestDownload`).
    @discardableResult
    public func changeSyncPreference(hash: String, to newPreference: SoundFontSyncPreference) throws -> SoundFontEntry {
        let descriptor = FetchDescriptor<SoundFontRecord>(predicate: #Predicate { $0.contentHash == hash })
        guard let record = try modelContext.fetch(descriptor).first, var entry = record.asSoundFontEntry else {
            throw SoundFontLibraryError.recordNotFound
        }
        guard entry.syncPreference != newPreference else { return entry }

        let sourceFolder = entry.syncPreference == .synced ? syncedFolder : localFolder
        guard let sourceFolder else { throw SoundFontLocationsError.iCloudContainerUnavailable }
        let sourceURL = sourceFolder.appendingPathComponent(entry.fileName)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw SoundFontLibraryError.notDownloadedOnThisDevice
        }
        guard let destinationFolder = newPreference == .synced ? syncedFolder : localFolder else {
            throw SoundFontLocationsError.iCloudContainerUnavailable
        }

        let destinationURL = uniqueDestinationURL(in: destinationFolder, preferredName: entry.fileName)
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)

        entry.fileName = destinationURL.lastPathComponent
        entry.syncPreference = newPreference
        record.update(from: entry)
        try modelContext.save()
        onChange?()
        return entry
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
    /// item whose `fileName` already matches a known record in this same location (a
    /// gigabyte-scale file should never be re-hashed on every launch/query update just to
    /// confirm nothing changed). Matches by `fileName` ALONE, not also `fileSize`: a
    /// `NSMetadataQuery` item's `NSMetadataItemFSSizeKey` isn't reliably populated for a
    /// ubiquity item that isn't fully synced/indexed yet (often reports `0`), which used to
    /// defeat this fast path and fall through to re-hashing — and re-hashing a file whose bytes
    /// aren't actually resident here yet fails, silently dropping the item from `seenHashes` and
    /// eventually (wrongly) pruning its perfectly-valid record. `fileName` alone is safe to
    /// match on within one location: `uniqueDestinationURL` already guarantees no two distinct
    /// soundfonts share a name in the same folder, and an actual user rename still gets caught
    /// correctly by the hash-based path below (no record has the NEW name yet, so it falls
    /// through, re-hashes, and finds/updates the existing record by hash). `.curated` entries
    /// are never pruned even when their file is gone (they can be re-downloaded — see
    /// `CuratedSoundFontCatalog`).
    private func reconcile(items: [DiskItem], syncPreference: SoundFontSyncPreference, requireConfirmedMiss: Bool) {
        let existing = (try? modelContext.fetch(FetchDescriptor<SoundFontRecord>())) ?? []
        let existingForLocation = existing.filter { $0.syncPreference == syncPreference.rawValue }
        var seenHashes: Set<String> = []

        for item in items {
            if let match = existingForLocation.first(where: { $0.fileName == item.fileName }) {
                seenHashes.insert(match.contentHash)
                missingSince[match.contentHash] = nil
                // Only trust a freshly-reported size when it's non-zero and different — a `0`
                // here is the unreliable-metadata case this whole match-by-name change exists
                // to tolerate, never a real update to apply.
                if item.fileSize > 0, item.fileSize != match.fileSize {
                    match.fileSize = item.fileSize
                }
                continue
            }
            // Presets are best-effort (`.dls`/a corrupt `.sf2` just indexes with an empty
            // list — see `importFile`'s own doc comment); only a hashing failure (unreadable
            // file) is fatal enough to skip indexing entirely.
            guard let hash = try? SoundFontHasher.sha256Hex(ofFileAt: item.url) else { continue }
            let presets = (try? SoundFontPresetReader.presets(at: item.url)) ?? []
            seenHashes.insert(hash)
            missingSince[hash] = nil
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
            let firstMissedAt = missingSince[record.contentHash] ?? Date()
            missingSince[record.contentHash] = firstMissedAt
            guard Date().timeIntervalSince(firstMissedAt) >= missingGracePeriod else { continue }
            modelContext.delete(record)
            missingSince[record.contentHash] = nil
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

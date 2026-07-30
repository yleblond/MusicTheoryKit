import XCTest
import SwiftData
@testable import AppCore
import SoundFontModel

/// `SoundFontLibrary` itself is tested directly here (not through `ImprovSession`) for the
/// `deduplicate()`/`delete(hash:)`/`wipeEverything()` cases specifically — these guard against a
/// real, confirmed bug (`ImprovSession.migrateSoundFontsFromFolderScanIfNeeded` used to insert a
/// soundfont record unconditionally rather than checking for an existing one by hash first, so
/// two devices could each end up with their own duplicate row for the exact same file, with
/// CloudKit syncing both forever after — see that method's own doc comment).
final class SoundFontLibraryTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([SoundFontRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testDeduplicateKeepsTheRecordWhoseFileIsActuallyResidentOnThisDevice() throws {
        let context = try makeContext()
        let localFolder = try makeFolder()
        try Data([0x01, 0x02, 0x03]).write(to: localFolder.appendingPathComponent("Bank.sf2"))

        let sharedHash = "duplicate-hash"
        // The resident copy: this device actually has these bytes locally.
        context.insert(SoundFontRecord(SoundFontEntry(
            hash: sharedHash, displayName: "Bank", fileName: "Bank.sf2", fileSize: 3,
            presets: [], dateAdded: Date(), syncPreference: .localOnly
        )))
        // The orphaned duplicate: same content hash, but this device never had this file — the
        // exact shape a duplicate created on a DIFFERENT device would take once CloudKit synced
        // its row here.
        context.insert(SoundFontRecord(SoundFontEntry(
            hash: sharedHash, displayName: "Bank (autre appareil)", fileName: "Bank-orphaned.sf2", fileSize: 3,
            presets: [], dateAdded: Date(), syncPreference: .synced
        )))
        try context.save()

        let library = SoundFontLibrary(modelContext: context)
        library.start(syncedFolder: nil, localFolder: localFolder, onChange: {})

        let remaining = try context.fetch(FetchDescriptor<SoundFontRecord>())
        XCTAssertEqual(remaining.count, 1, "the duplicate group is merged down to one row")
        XCTAssertEqual(remaining.first?.fileName, "Bank.sf2", "keeps the copy whose file is actually resident on this device")
    }

    func testDeleteRemovesEveryRecordSharingTheHashNotJustTheFirst() throws {
        let context = try makeContext()
        let localFolder = try makeFolder()
        let syncedFolder = try makeFolder()
        try Data([0x01, 0x02, 0x03]).write(to: localFolder.appendingPathComponent("Bank.sf2"))
        try Data([0x01, 0x02, 0x03]).write(to: syncedFolder.appendingPathComponent("Bank.sf2"))

        let sharedHash = "duplicate-hash"
        context.insert(SoundFontRecord(SoundFontEntry(
            hash: sharedHash, displayName: "Bank", fileName: "Bank.sf2", fileSize: 3,
            presets: [], dateAdded: Date(), syncPreference: .localOnly
        )))
        context.insert(SoundFontRecord(SoundFontEntry(
            hash: sharedHash, displayName: "Bank", fileName: "Bank.sf2", fileSize: 3,
            presets: [], dateAdded: Date(), syncPreference: .synced
        )))
        try context.save()

        // This test exercises `delete(hash:)` against an already-duplicated store directly
        // (matching the exact "delete acted strangely" symptom reported before this fix: only
        // the first matching row used to be removed, silently leaving the other behind) —
        // bypasses `start()`'s own automatic `deduplicate()`, which would otherwise merge the
        // duplicates away before `delete` ever got a chance to run against them.
        let library = SoundFontLibrary(modelContext: context)
        library.setFoldersForTesting(syncedFolder: syncedFolder, localFolder: localFolder)

        let deleted = library.delete(hash: sharedHash)
        XCTAssertNotNil(deleted)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SoundFontRecord>()).isEmpty, "both duplicate rows are gone")
        XCTAssertFalse(FileManager.default.fileExists(atPath: localFolder.appendingPathComponent("Bank.sf2").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: syncedFolder.appendingPathComponent("Bank.sf2").path))
    }

    func testWipeEverythingRemovesAllRecordsAndFiles() throws {
        let context = try makeContext()
        let localFolder = try makeFolder()
        let syncedFolder = try makeFolder()
        try Data([0x01]).write(to: localFolder.appendingPathComponent("Local.sf2"))
        try Data([0x02]).write(to: syncedFolder.appendingPathComponent("Synced.sf2"))

        context.insert(SoundFontRecord(SoundFontEntry(
            hash: "hash-local", displayName: "Local", fileName: "Local.sf2", fileSize: 1,
            presets: [], dateAdded: Date(), syncPreference: .localOnly
        )))
        context.insert(SoundFontRecord(SoundFontEntry(
            hash: "hash-synced", displayName: "Synced", fileName: "Synced.sf2", fileSize: 1,
            presets: [], dateAdded: Date(), syncPreference: .synced
        )))
        try context.save()

        let library = SoundFontLibrary(modelContext: context)
        library.setFoldersForTesting(syncedFolder: syncedFolder, localFolder: localFolder)

        library.wipeEverything()

        XCTAssertTrue(try context.fetch(FetchDescriptor<SoundFontRecord>()).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localFolder.appendingPathComponent("Local.sf2").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: syncedFolder.appendingPathComponent("Synced.sf2").path))
    }
}

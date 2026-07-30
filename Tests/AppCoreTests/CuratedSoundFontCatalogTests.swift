import XCTest
@testable import AppCore

/// Structural integrity checks on the embedded catalog itself (see `CuratedSoundFontCatalog
/// .entries`'s own doc comment) — every field here was meant to be filled in by hand at curation
/// time, so these are the kind of mistake a human curator could make (a typo'd category, a
/// non-hex hash, a size of zero) that a compiler can't catch on its own.
final class CuratedSoundFontCatalogTests: XCTestCase {
    private static let hexDigits = CharacterSet(charactersIn: "0123456789abcdef")

    func testEveryEntryHasAWellFormedSHA256() {
        for entry in CuratedSoundFontCatalog.entries {
            XCTAssertEqual(entry.sha256.count, 64, "\(entry.id) should have a 64-character hex sha256")
            XCTAssertTrue(
                entry.sha256.unicodeScalars.allSatisfy { Self.hexDigits.contains($0) },
                "\(entry.id)'s sha256 should be lowercase hex"
            )
        }
    }

    func testEveryEntryHasAPositiveSize() {
        for entry in CuratedSoundFontCatalog.entries {
            XCTAssertGreaterThan(entry.sizeBytes, 0, "\(entry.id) should have a real, measured size")
        }
    }

    func testEveryEntryReferencesAKnownCategory() {
        let categoryIds = Set(CuratedSoundFontCatalog.categories.map(\.id))
        for entry in CuratedSoundFontCatalog.entries {
            XCTAssertTrue(categoryIds.contains(entry.categoryId), "\(entry.id) references unknown category '\(entry.categoryId)'")
        }
    }

    func testEveryEntryIsAFormatThisAppCanActuallyLoad() {
        // `AVAudioUnitSampler` cannot read `.sf3` — see `SoundFontCatalogEntry.Format`'s own doc
        // comment. `installableEntries` is the defensive filter; this test asserts the catalog
        // never actually needs it to filter anything out in practice.
        XCTAssertEqual(CuratedSoundFontCatalog.installableEntries.count, CuratedSoundFontCatalog.entries.count)
    }

    func testEveryEntryDownloadsOverHTTPS() {
        for entry in CuratedSoundFontCatalog.entries {
            XCTAssertEqual(entry.downloadURL.scheme, "https", "\(entry.id) should download over HTTPS")
        }
    }

    func testEveryEntryHasANonEmptyLocalizedSummary() {
        for entry in CuratedSoundFontCatalog.entries {
            XCTAssertFalse(entry.localizedSummary(.fr).isEmpty, "\(entry.id) should have a French summary")
            XCTAssertFalse(entry.localizedSummary(.en).isEmpty, "\(entry.id) should have an English summary")
        }
    }

    func testNoTwoEntriesShareAnId() {
        let ids = CuratedSoundFontCatalog.entries.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "catalog entry ids must be unique")
    }
}

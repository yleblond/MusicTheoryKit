import XCTest
@testable import AppCore

/// `SoundFontDownloadPolicy.decide` is a pure function specifically so every one of these cases
/// is testable without touching a real filesystem/iCloud account — see that type's own doc
/// comment for the invariant every case here checks in some way: the local free-space floor is
/// never crossed, even for a favorite.
final class SoundFontDownloadPolicyTests: XCTestCase {
    private let plentyOfSpace: Int64 = 500_000_000_000 // 500 GB

    func testSmallFileAutoDownloadsWhenSpaceIsPlentiful() {
        let decision = SoundFontDownloadPolicy.decide(
            fileSize: 50_000_000, currentFreeSpace: plentyOfSpace, profile: .standard,
            isFavorite: false, recentlyUsedOnThisDevice: false
        )
        XCTAssertEqual(decision, .autoDownload)
    }

    func testMidSizedFileAsksBeforeDownloadingWhenNotAPriority() {
        let decision = SoundFontDownloadPolicy.decide(
            fileSize: 1_000_000_000, currentFreeSpace: plentyOfSpace, profile: .standard,
            isFavorite: false, recentlyUsedOnThisDevice: false
        )
        XCTAssertEqual(decision, .askUser(reason: .largeFile))
    }

    func testFavoriteSkipsThePromptForAMidSizedFile() {
        let decision = SoundFontDownloadPolicy.decide(
            fileSize: 1_000_000_000, currentFreeSpace: plentyOfSpace, profile: .standard,
            isFavorite: true, recentlyUsedOnThisDevice: false
        )
        XCTAssertEqual(decision, .autoDownload)
    }

    func testRecentlyUsedSkipsThePromptJustLikeAFavoriteDoes() {
        let decision = SoundFontDownloadPolicy.decide(
            fileSize: 1_000_000_000, currentFreeSpace: plentyOfSpace, profile: .standard,
            isFavorite: false, recentlyUsedOnThisDevice: true
        )
        XCTAssertEqual(decision, .autoDownload)
    }

    func testHugeFileNeverAutoDownloadsEvenAsAFavoriteOnlyAsksInstead() {
        // Standard profile's promptSizeCeiling is 2 GB — above that, even a favorite only gets
        // asked, never silently downloaded (never skip two caution steps at once).
        let decision = SoundFontDownloadPolicy.decide(
            fileSize: 5_000_000_000, currentFreeSpace: plentyOfSpace, profile: .standard,
            isFavorite: true, recentlyUsedOnThisDevice: false
        )
        XCTAssertEqual(decision, .askUser(reason: .largeFavorite))
    }

    func testLowLocalSpaceStaysMetadataOnlyWhenNotAPriority() {
        // Standard profile's floor is 10 GB — only ~9.97 GB would remain after this download.
        let decision = SoundFontDownloadPolicy.decide(
            fileSize: 50_000_000, currentFreeSpace: 10_020_000_000, profile: .standard,
            isFavorite: false, recentlyUsedOnThisDevice: false
        )
        XCTAssertEqual(decision, .metadataOnly)
    }

    func testLowLocalSpaceNeverAutoDownloadsEvenForAFavoriteOnlyAsksInstead() {
        let decision = SoundFontDownloadPolicy.decide(
            // Standard profile's floor is 10 GB — only ~9.97 GB would remain after this download.
            fileSize: 50_000_000, currentFreeSpace: 10_020_000_000, profile: .standard,
            isFavorite: true, recentlyUsedOnThisDevice: false
        )
        XCTAssertEqual(decision, .askUser(reason: .lowLocalSpaceButHighPriority))
    }

    func testEconomicalProfileIsStricterThanGenerousForTheSameFile() {
        let fileSize: Int64 = 300_000_000
        let economical = SoundFontDownloadPolicy.decide(
            fileSize: fileSize, currentFreeSpace: plentyOfSpace, profile: .economical,
            isFavorite: false, recentlyUsedOnThisDevice: false
        )
        let generous = SoundFontDownloadPolicy.decide(
            fileSize: fileSize, currentFreeSpace: plentyOfSpace, profile: .generous,
            isFavorite: false, recentlyUsedOnThisDevice: false
        )
        XCTAssertEqual(economical, .askUser(reason: .largeFile))
        XCTAssertEqual(generous, .autoDownload)
    }
}

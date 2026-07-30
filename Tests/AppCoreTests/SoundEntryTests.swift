import XCTest
import SoundFontModel
@testable import AppCore

/// `SoundEntry` is keyed by soundfont content hash, not path (see `ImprovSession
/// .migrateSoundEntriesToHashKeyedIfNeeded` for why: a `.sf2` can be freely renamed/moved).
/// `LegacySoundEntry` is the OLD, path-keyed on-disk shape `migrateSoundSettingsFromJSONIfNeeded`
/// still needs to read once from a pre-existing `sound-settings.json` — these tests guard both
/// shapes independently, plus the multi-preset behavior (`preset` was added after
/// `sound-settings.json` was already in use on real installs: old files with no `preset` key at
/// all must still decode as `nil`, and a single soundfont can carry more than one entry as long
/// as `preset` differs).
final class SoundEntryTests: XCTestCase {
    func testLegacySoundEntryDecodesPreExistingJSONWithNoPresetKeyAsNilPreset() throws {
        let json = """
        {"path": "OrchestralLib/Strings/Violin.sf2", "alias": "Violon chaud", "isFavorite": true}
        """
        let entry = try JSONDecoder().decode(LegacySoundEntry.self, from: Data(json.utf8))

        XCTAssertEqual(entry.path, "OrchestralLib/Strings/Violin.sf2")
        XCTAssertEqual(entry.alias, "Violon chaud")
        XCTAssertTrue(entry.isFavorite)
        XCTAssertNil(entry.preset)
    }

    func testSoundEntryRoundTripsAPresetIdentityThroughJSON() throws {
        let entry = SoundEntry(
            soundFontHash: "abc123",
            alias: "Orgue d'eglise",
            isFavorite: true,
            preset: SoundFontPresetIdentity(program: 19, bank: 0)
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(SoundEntry.self, from: data)

        XCTAssertEqual(decoded, entry)
    }

    func testTwoEntriesForTheSameSoundFontWithDifferentPresetsAreNotEqual() {
        let piano = SoundEntry(soundFontHash: "abc123", preset: SoundFontPresetIdentity(program: 0, bank: 0))
        let organ = SoundEntry(soundFontHash: "abc123", preset: SoundFontPresetIdentity(program: 19, bank: 0))

        XCTAssertNotEqual(piano, organ)
    }
}

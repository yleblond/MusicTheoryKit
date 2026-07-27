import XCTest
import SoundFontModel
@testable import AppCore

/// `SoundEntry.preset` was added after `sound-settings.json` was already in use on real
/// installs — these tests guard the two things that matter for that: old files (no `preset`
/// key at all) must still decode, and a `path` can now carry more than one entry as long as
/// `preset` differs (what multi-preset `.sf2` support in a later phase will rely on).
final class SoundEntryTests: XCTestCase {
    func testDecodesPreExistingJSONWithNoPresetKeyAsNilPreset() throws {
        let json = """
        {"path": "OrchestralLib/Strings/Violin.sf2", "alias": "Violon chaud", "isFavorite": true}
        """
        let entry = try JSONDecoder().decode(SoundEntry.self, from: Data(json.utf8))

        XCTAssertEqual(entry.path, "OrchestralLib/Strings/Violin.sf2")
        XCTAssertEqual(entry.alias, "Violon chaud")
        XCTAssertTrue(entry.isFavorite)
        XCTAssertNil(entry.preset)
    }

    func testRoundTripsAPresetIdentityThroughJSON() throws {
        let entry = SoundEntry(
            path: "GMBank.sf2",
            alias: "Orgue d'eglise",
            isFavorite: true,
            preset: SoundFontPresetIdentity(program: 19, bank: 0)
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(SoundEntry.self, from: data)

        XCTAssertEqual(decoded, entry)
    }

    func testTwoEntriesForTheSamePathWithDifferentPresetsAreNotEqual() {
        let piano = SoundEntry(path: "GMBank.sf2", preset: SoundFontPresetIdentity(program: 0, bank: 0))
        let organ = SoundEntry(path: "GMBank.sf2", preset: SoundFontPresetIdentity(program: 19, bank: 0))

        XCTAssertNotEqual(piano, organ)
    }
}

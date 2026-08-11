import XCTest
@testable import MusicTheoryKit

final class TonnetzTests: XCTestCase {

    func testPitchClassAtOrigin() {
        XCTAssertEqual(Tonnetz.pitchClass(at: TonnetzCoordinate(q: 0, r: 0)).value, 0)
    }

    func testPitchClassMovesBySevenPerFifthStep() {
        XCTAssertEqual(Tonnetz.pitchClass(at: TonnetzCoordinate(q: 1, r: 0)).value, 7)
        XCTAssertEqual(Tonnetz.pitchClass(at: TonnetzCoordinate(q: 2, r: 0)).value, 2)
    }

    func testPitchClassMovesByFourPerMajorThirdStep() {
        XCTAssertEqual(Tonnetz.pitchClass(at: TonnetzCoordinate(q: 0, r: 1)).value, 4)
        XCTAssertEqual(Tonnetz.pitchClass(at: TonnetzCoordinate(q: 0, r: 2)).value, 8)
    }

    func testMinorThirdFallsOutAsTheThirdTriangleSide() {
        // (q+1,r) -> (q,r+1) should be a -3 semitone step (the minor third completing the
        // triangle) with no separate axis needed.
        let a = Tonnetz.pitchClass(at: TonnetzCoordinate(q: 1, r: 0))
        let b = Tonnetz.pitchClass(at: TonnetzCoordinate(q: 0, r: 1))
        XCTAssertEqual((b.value - a.value + 12) % 12, 9) // +9 == -3 mod 12
    }

    func testMajorTriangleAnchoredAtOriginIsCMajor() {
        let nodes = Tonnetz.nodes(ofQuality: .major, anchoredAt: TonnetzCoordinate(q: 0, r: 0))
        let pitchClasses = Set(nodes.map { Tonnetz.pitchClass(at: $0).value })
        XCTAssertEqual(pitchClasses, [0, 4, 7])
    }

    func testMinorTriangleAnchoredAtOriginIsCMinor() {
        let nodes = Tonnetz.nodes(ofQuality: .minor, anchoredAt: TonnetzCoordinate(q: 0, r: 0))
        let pitchClasses = Set(nodes.map { Tonnetz.pitchClass(at: $0).value })
        XCTAssertEqual(pitchClasses, [0, 3, 7])
    }

    func testParallelSwapsQualitySameRootSameCoordinate() {
        let cMajor = Tonnetz.triad(quality: .major, anchoredAt: TonnetzCoordinate(q: 0, r: 0))
        let cMinor = Tonnetz.parallel(of: cMajor)
        XCTAssertEqual(cMinor.quality, .minor)
        XCTAssertEqual(cMinor.root.value, 0)
        XCTAssertEqual(cMinor.coordinate, cMajor.coordinate)
        // Involution.
        XCTAssertEqual(Tonnetz.parallel(of: cMinor).root.value, cMajor.root.value)
        XCTAssertEqual(Tonnetz.parallel(of: cMinor).quality, cMajor.quality)
    }

    func testRelativeOfCMajorIsAMinor() {
        let cMajor = Tonnetz.triad(quality: .major, anchoredAt: TonnetzCoordinate(q: 0, r: 0))
        let aMinor = Tonnetz.relative(of: cMajor)
        XCTAssertEqual(aMinor.quality, .minor)
        XCTAssertEqual(aMinor.root.value, 9)
        // Round-trips back to C major.
        let backToMajor = Tonnetz.relative(of: aMinor)
        XCTAssertEqual(backToMajor.quality, .major)
        XCTAssertEqual(backToMajor.root.value, 0)
    }

    func testLeadingToneExchangeOfCMajorIsEMinor() {
        let cMajor = Tonnetz.triad(quality: .major, anchoredAt: TonnetzCoordinate(q: 0, r: 0))
        let eMinor = Tonnetz.leadingToneExchange(of: cMajor)
        XCTAssertEqual(eMinor.quality, .minor)
        XCTAssertEqual(eMinor.root.value, 4)
        // Round-trips back to C major.
        let backToMajor = Tonnetz.leadingToneExchange(of: eMinor)
        XCTAssertEqual(backToMajor.quality, .major)
        XCTAssertEqual(backToMajor.root.value, 0)
    }

    func testPaddedTileHasTwelveDistinctPitchClassesInPrimary() {
        let tile = Tonnetz.paddedTile()
        let primaryPitchClasses = Set(tile.primary.map { Tonnetz.pitchClass(at: $0).value })
        XCTAssertEqual(tile.primary.count, 12)
        XCTAssertEqual(primaryPitchClasses.count, 12)
        XCTAssertEqual(primaryPitchClasses, Set(0...11))
    }

    func testPaddedTileHaloOnlyRepeatsPrimaryPitchClasses() {
        let tile = Tonnetz.paddedTile()
        let primaryPitchClasses = Set(tile.primary.map { Tonnetz.pitchClass(at: $0).value })
        let haloPitchClasses = Set(tile.halo.map { Tonnetz.pitchClass(at: $0).value })
        XCTAssertEqual(tile.halo.count, 18)
        XCTAssertTrue(haloPitchClasses.isSubset(of: primaryPitchClasses))
    }

    func testMatchingTriadsExactTriadReturnsOneMatch() {
        let matches = Tonnetz.matchingTriads(forHeldPitchClasses: [PitchClass(0), PitchClass(4), PitchClass(7)])
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.root.value, 0)
        XCTAssertEqual(matches.first?.quality, .major)
    }

    func testMatchingTriadsDyadReturnsBothMajorAndMinorCandidates() {
        let matches = Tonnetz.matchingTriads(forHeldPitchClasses: [PitchClass(0), PitchClass(7)])
        let rootsAndQualities = Set(matches.map { "\($0.root.value)-\($0.quality.rawValue)" })
        XCTAssertEqual(rootsAndQualities, ["0-major", "0-minor"])
    }

    func testMatchingTriadsTooFewOrTooManyNotesReturnsNoMatches() {
        XCTAssertTrue(Tonnetz.matchingTriads(forHeldPitchClasses: [PitchClass(0)]).isEmpty)
        XCTAssertTrue(Tonnetz.matchingTriads(forHeldPitchClasses: [PitchClass(0), PitchClass(2), PitchClass(4), PitchClass(7)]).isEmpty)
    }

    func testCoordinateForRootPrefersPrimaryOverHalo() {
        let tile = Tonnetz.paddedTile()
        let coordinate = Tonnetz.coordinate(forRoot: PitchClass(7), in: tile.primary + tile.halo)
        XCTAssertNotNil(coordinate)
        XCTAssertTrue(tile.primary.contains(coordinate!))
    }

    func testMidiPitchMatchesPitchClassModulo12() {
        let coordinate = TonnetzCoordinate(q: 2, r: 1)
        let midi = Tonnetz.midiPitch(at: coordinate)
        let pitchClass = Tonnetz.pitchClass(at: coordinate)
        XCTAssertEqual(((midi % 12) + 12) % 12, pitchClass.value)
    }
}

import XCTest
@testable import PieceModel

final class EventsTests: XCTestCase {

    func testChordEventDefaultsAndFields() {
        let chord = ChordReference(root: 0, chordTemplateID: "Ma7")
        let event = ChordEvent(measure: 3, beat: 2.5, durationBeats: 1.5, chord: chord)
        XCTAssertEqual(event.measure, 3)
        XCTAssertEqual(event.beat, 2.5)
        XCTAssertEqual(event.durationBeats, 1.5)
        XCTAssertEqual(event.chord, chord)
        XCTAssertEqual(event.inversion, 0)
        XCTAssertNil(event.bassOverride)
        XCTAssertEqual(event.playingStyle, .simultaneous)
    }

    func testChordEventDistinctInstancesGetDistinctIDsByDefault() {
        let chord = ChordReference(root: 0, chordTemplateID: "Ma7")
        let a = ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: chord)
        let b = ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: chord)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testMelodyEventDefaultVelocity() {
        let event = MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60)
        XCTAssertEqual(event.velocity, 100)
        XCTAssertEqual(event.pitch, 60)
    }

    func testFragmentPlacementResolvedFragmentAppliesNoTransformsByDefault() {
        let fragment = MelodicFragment(name: "motif", referenceMode: .fromFirstNote, intervals: [4, 7], noteDurations: [1, 1, 1])
        let placement = FragmentPlacement(fragmentID: fragment.id, measure: 1, beat: 1, basePitch: 60)
        let resolved = placement.resolvedFragment(from: fragment)
        XCTAssertEqual(resolved.absolutePitches(basePitch: 60), fragment.absolutePitches(basePitch: 60))
        XCTAssertEqual(resolved.noteDurations, fragment.noteDurations)
    }

    func testFragmentPlacementResolvedFragmentAppliesTransformsInOrder() {
        // Order is fixed: retrograde, then inversion, then acceleration.
        let fragment = MelodicFragment(name: "motif", referenceMode: .fromFirstNote, intervals: [4, 7], noteDurations: [1, 1, 1])
        let placement = FragmentPlacement(
            fragmentID: fragment.id,
            measure: 1,
            beat: 1,
            basePitch: 60,
            retrograde: true,
            inversionPivot: 0,
            accelerationFactor: 2.0
        )
        let resolved = placement.resolvedFragment(from: fragment)
        let expected = fragment.retrograded().inverted(aroundPivot: 0).accelerated(by: 2.0)
        XCTAssertEqual(resolved.absolutePitches(basePitch: 60), expected.absolutePitches(basePitch: 60))
        XCTAssertEqual(resolved.noteDurations, expected.noteDurations)
    }
}

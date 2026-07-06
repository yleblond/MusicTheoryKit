import XCTest
@testable import RecognitionEngine
@testable import MusicTheoryKit

final class RecognitionEngineTests: XCTestCase {

    // MARK: - Chords

    func testRecognizesBareMajorTriadAsATriadNotA7thChord() {
        // A plain C-E-G must resolve to the "Ma" triad, not get force-fit into "Ma7"
        // (which it also partially overlaps) just because 7th chords used to be the only
        // templates in the vocabulary.
        let engine = RecognitionEngine()
        for pitch in [60, 64, 67] { engine.noteOn(pitch: pitch) } // C E G
        let chord = engine.recognizeChord()
        XCTAssertEqual(chord?.root, PitchClass(0))
        XCTAssertEqual(chord?.chordTemplateID, "Ma")
        XCTAssertEqual(chord?.confidence, 1.0)
    }

    func testRecognizesRootPositionSeventhChord() {
        let engine = RecognitionEngine()
        for pitch in [60, 64, 67, 71] { engine.noteOn(pitch: pitch) } // C E G B -> Cmaj7
        let chord = engine.recognizeChord()
        XCTAssertEqual(chord?.root, PitchClass(0))
        XCTAssertEqual(chord?.chordTemplateID, "Ma7")
        XCTAssertEqual(chord?.confidence, 1.0)
    }

    func testRecognizesChordRegardlessOfOctaveOrOrder() {
        let engine = RecognitionEngine()
        for pitch in [74, 43, 55, 84] { engine.noteOn(pitch: pitch) } // D3 F3(ish) A3 D6 spread across octaves, pitch classes D F A + D again
        // D(74->2) F(43->7? let's just rely on pitch classes: 74%12=2(D), 43%12=7(G) -- adjust
        engine.reset()
        // Dm7 spread: D2(38), F3(53), A4(69), C5(72)
        for pitch in [38, 53, 69, 72] { engine.noteOn(pitch: pitch) }
        let chord = engine.recognizeChord()
        XCTAssertEqual(chord?.root, PitchClass(2))
        XCTAssertEqual(chord?.chordTemplateID, "mi7")
        XCTAssertEqual(chord?.confidence, 1.0)
    }

    func testReleasingANoteUpdatesTheHeldChord() {
        let engine = RecognitionEngine()
        for pitch in [60, 64, 67, 71] { engine.noteOn(pitch: pitch) } // Cmaj7
        engine.noteOff(pitch: 71) // drop the 7th -> now a bare C major triad
        let chord = engine.recognizeChord(minimumConfidence: 0.9)
        XCTAssertEqual(chord?.chordTemplateID, "Ma")
        XCTAssertEqual(chord?.confidence, 1.0)
    }

    func testFewerThanTwoHeldNotesRecognizesNoChord() {
        let engine = RecognitionEngine()
        engine.noteOn(pitch: 60)
        XCTAssertNil(engine.recognizeChord())
    }

    func testPartialOverlapBelowThresholdIsRejected() {
        let engine = RecognitionEngine()
        engine.noteOn(pitch: 60) // C
        engine.noteOn(pitch: 61) // C#, clashes with everything
        XCTAssertNil(engine.recognizeChord(minimumConfidence: 0.9))
    }

    // MARK: - Modes

    func testRecognizesCMajorFromItsScaleNotes() {
        let engine = RecognitionEngine()
        let base = Date()
        for (i, pitch) in [60, 62, 64, 65, 67, 69, 71].enumerated() { // C D E F G A B
            engine.noteOn(pitch: pitch, at: base.addingTimeInterval(Double(i) * 0.1))
        }
        let modes = engine.recognizeModes(at: base.addingTimeInterval(0.7))
        XCTAssertTrue(modes.contains { $0.tonic == PitchClass(0) && $0.scaleID == "ionian" })
    }

    func testAmbiguousRelativeModesAllAppearAsCandidates() {
        // C major and A aeolian share every pitch class, so both should surface.
        let engine = RecognitionEngine()
        let base = Date()
        for (i, pitch) in [60, 62, 64, 65, 67, 69, 71].enumerated() {
            engine.noteOn(pitch: pitch, at: base.addingTimeInterval(Double(i) * 0.1))
        }
        let modes = engine.recognizeModes(at: base.addingTimeInterval(0.7), maxResults: 10)
        let scaleIDs = Set(modes.filter { $0.confidence >= 0.99 }.map { "\($0.tonic.value):\($0.scaleID)" })
        XCTAssertTrue(scaleIDs.contains("0:ionian"))
        XCTAssertTrue(scaleIDs.contains("9:aeolian"))
    }

    func testDecayMakesOldNotesStopCounting() {
        let engine = RecognitionEngine(modeHalfLife: 1.0)
        let base = Date()
        // Play a full C major scale, then long after, play just a lone F# far outside it.
        for (i, pitch) in [60, 62, 64, 65, 67, 69, 71].enumerated() {
            engine.noteOn(pitch: pitch, at: base.addingTimeInterval(Double(i) * 0.1))
        }
        engine.noteOn(pitch: 66, at: base.addingTimeInterval(30)) // F#, 30s later: everything else has decayed away
        let modes = engine.recognizeModes(at: base.addingTimeInterval(30), activityThreshold: 0.01)
        XCTAssertFalse(modes.contains { $0.tonic == PitchClass(0) && $0.scaleID == "ionian" })
    }

    func testNoRecentActivityRecognizesNoModes() {
        let engine = RecognitionEngine()
        XCTAssertEqual(engine.recognizeModes(), [])
    }

    func testResetClearsHeldNotesAndHistory() {
        let engine = RecognitionEngine()
        engine.noteOn(pitch: 60)
        engine.noteOn(pitch: 64)
        engine.reset()
        XCTAssertNil(engine.recognizeChord())
        XCTAssertEqual(engine.recognizeModes(activityThreshold: 0), [])
    }
}

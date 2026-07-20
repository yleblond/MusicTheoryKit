import XCTest
import RecognitionEngine
import MusicTheoryKit
import PieceModel
@testable import AppCore

// Pure "which state should the LUMI show" decision logic — see
// Sources/SanityChecks/main.swift's mirrored section for why this is tested in isolation
// from liveInputQueue/CoreMIDI (ImprovSession.syncLumiLiveModeIfActive).
final class LumiLiveModeTests: XCTestCase {
    func testFallsBackToPianoWithNoTracks() {
        XCTAssertEqual(ImprovSession.LumiLiveModeLastState.current(for: []), .piano)
    }

    func testUsesTheMergedTrackWhenItIsListening() {
        let mode = RecognizedMode(tonic: PitchClass(0), scaleID: "ionian", confidence: 0.9)
        let tracks = [
            TrackInfo(id: .computerKeyboard, label: "t1", isListening: false, canHaveSound: true, recognizedModes: [mode]),
            TrackInfo(id: .midiMerged, label: "MIDI (fusionne)", isListening: true, canHaveSound: true, recognizedModes: [mode]),
        ]
        XCTAssertEqual(ImprovSession.LumiLiveModeLastState.current(for: tracks), .mode(mode))
    }

    func testFallsBackToPianoWhenListeningTrackHasNoRecognizedMode() {
        let tracks = [TrackInfo(id: .midiMerged, label: "MIDI (fusionne)", isListening: true, canHaveSound: true, recognizedModes: [])]
        XCTAssertEqual(ImprovSession.LumiLiveModeLastState.current(for: tracks), .piano)
    }

    /// The bug this guards against: under `MIDIFusionMode.individual`, several MIDI devices
    /// can each have their own listening track (`refreshTracks` labels them `"MIDI : \(name)"`)
    /// — picking "the first listening track" would let an unrelated keyboard that happens to
    /// sort earlier drive the LUMI's own display. Only the track whose label names the LUMI
    /// should be consulted.
    func testIndividualModePicksTheLumiNamedTrackNotWhicheverSortsFirst() {
        let otherKeyboardMode = RecognizedMode(tonic: PitchClass(2), scaleID: "dorian", confidence: 0.9)
        let lumiMode = RecognizedMode(tonic: PitchClass(0), scaleID: "ionian", confidence: 0.9)
        let tracks = [
            TrackInfo(id: .midiSource(0), label: "MIDI : Some Other Keyboard", isListening: true, canHaveSound: true, recognizedModes: [otherKeyboardMode]),
            TrackInfo(id: .midiSource(1), label: "MIDI : LUMI Keys BLOCK", isListening: true, canHaveSound: true, recognizedModes: [lumiMode]),
        ]
        XCTAssertEqual(ImprovSession.LumiLiveModeLastState.current(for: tracks), .mode(lumiMode))
    }

    func testIndividualModeFallsBackToPianoWhenTheLumiTrackIsntListening() {
        let otherKeyboardMode = RecognizedMode(tonic: PitchClass(2), scaleID: "dorian", confidence: 0.9)
        let tracks = [
            TrackInfo(id: .midiSource(0), label: "MIDI : Some Other Keyboard", isListening: true, canHaveSound: true, recognizedModes: [otherKeyboardMode]),
            TrackInfo(id: .midiSource(1), label: "MIDI : LUMI Keys BLOCK", isListening: false, canHaveSound: true, recognizedModes: []),
        ]
        XCTAssertEqual(ImprovSession.LumiLiveModeLastState.current(for: tracks), .piano)
    }
}

final class LumiGuideDisplayTests: XCTestCase {
    func testFallsBackToPianoWhenNoStepReference() {
        XCTAssertEqual(ImprovSession.LumiGuideDisplayLastState.current(forStepMode: nil), .piano)
    }

    func testShowsGuideMapForAMappedScale() {
        let reference = ModeReference(tonic: 0, scaleID: "ionian")
        XCTAssertEqual(ImprovSession.LumiGuideDisplayLastState.current(forStepMode: reference), .guideMap(reference))
    }

    func testFallsBackToPianoForAnUnmappedScale() {
        let reference = ModeReference(tonic: 0, scaleID: "melodic_minor")
        XCTAssertEqual(ImprovSession.LumiGuideDisplayLastState.current(forStepMode: reference), .piano)
    }
}

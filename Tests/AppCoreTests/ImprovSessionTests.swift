import XCTest
import SwiftData
@testable import AppCore
@testable import PieceModel
import MIDIEngine
import MusicTheoryKit
import LLMEngine
import SoundTrackModel
import SoundFontModel
import AudioEngine
import Localization

/// A fresh `ImprovSession` backed by an in-memory SwiftData store — every test that exercises
/// any `migrate...FromJSONIfNeeded`/LLM-connection/color-palette/etc. method needs its own
/// isolated container, not the real on-disk one `ImprovSession()` lazily creates on first use
/// (which would leak state across tests and even across separate `swift test` runs). One
/// shared schema, mirroring `ImprovSession.modelContainer`'s own `Schema([...])` list exactly.
func makeTestSession() -> ImprovSession {
    let schema = Schema([
        LLMConnectionRecord.self,
        ColorPaletteRecord.self,
        ChordProgressionTemplateRecord.self,
        LanguageSettingRecord.self,
        LumiSettingsRecord.self,
        SpectrogramSettingsRecord.self,
        NoteColorSettingsRecord.self,
        MicrophoneCalibrationSettingsRecord.self,
        SoundEntryRecord.self,
        GuideSequenceRecord.self,
        SceneRecord.self,
        SoundTrackRecord.self,
        PromptSnippetRecord.self,
        CompositionDescriptionRecord.self,
        PieceRecord.self,
    ])
    let container = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    return ImprovSession(modelContainer: container)
}

final class ImprovSessionTests: XCTestCase {

    func testLoadDemoPieceSetsPieceAndLogsIt() {
        let session = ImprovSession()
        XCTAssertNil(session.piece)
        session.loadDemoPiece()
        XCTAssertEqual(session.piece?.title, "ii-V-I demo")
        XCTAssertTrue(session.log.contains { $0.contains("ii-V-I demo") })
    }

    func testPlayWithoutAPieceLoadedThrows() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.play()) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noPieceLoaded)
        }
    }

    func testPlayTracksPlaybackStateSynchronouslyThenClearsItWhenFinished() throws {
        let session = ImprovSession()
        try session.start()

        let section = Section(
            name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
            chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 1, chord: ChordReference(root: 0, chordTemplateID: "Ma7"))]
        )
        // A very fast tempo so playback finishes almost immediately and the test doesn't
        // need to sleep long to observe the "cleared after finishing" half of the behavior.
        let piece = Piece(title: "fast", tempoBPM: 6000, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section])
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try JSONEncoder().encode(piece).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.loadPiece(fromJSONFile: tempFile.path)

        try session.play()
        XCTAssertTrue(session.isPlaying)
        XCTAssertEqual(session.playbackTimeline.count, 1)
        XCTAssertEqual(session.playbackTimeline.first?.chord, ChordReference(root: 0, chordTemplateID: "Ma7"))
        XCTAssertEqual(session.playbackCurrentChordIndex, 0)

        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(session.isPlaying)
        XCTAssertNil(session.playbackCurrentChordIndex)
        XCTAssertTrue(session.playbackHeldPitches.isEmpty)
    }

    private func loadTemporaryPiece(_ piece: Piece, into session: ImprovSession) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try JSONEncoder().encode(piece).write(to: url)
        try session.loadPiece(fromJSONFile: url.path)
    }

    func testSetPieceTrackInstrumentUpdatesTrackAndLogs() throws {
        let session = ImprovSession()
        let track = Track(name: "lead", instrument: "")
        let section = Section(name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"), tracks: [track])
        try loadTemporaryPiece(Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section]), into: session)

        try session.setPieceTrackInstrument(sectionIndex: 0, trackIndex: 0, instrumentName: "mcb.sf2")

        XCTAssertEqual(session.piece?.sections[0].tracks[0].instrument, "mcb.sf2")
        XCTAssertTrue(session.log.contains { $0.contains("mcb.sf2") })
    }

    func testSetPieceTrackInstrumentNilRevertsToEmptyString() throws {
        let session = ImprovSession()
        let track = Track(name: "lead", instrument: "mcb.sf2")
        let section = Section(name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"), tracks: [track])
        try loadTemporaryPiece(Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section]), into: session)

        try session.setPieceTrackInstrument(sectionIndex: 0, trackIndex: 0, instrumentName: nil)

        XCTAssertEqual(session.piece?.sections[0].tracks[0].instrument, "")
    }

    func testSetPieceTrackInstrumentWithInvalidSectionIndexThrows() {
        let session = ImprovSession()
        session.loadDemoPiece()
        XCTAssertThrowsError(try session.setPieceTrackInstrument(sectionIndex: 99, trackIndex: 0, instrumentName: "mcb.sf2")) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .invalidPieceSectionIndex)
        }
    }

    func testSetPieceTrackInstrumentWithInvalidTrackIndexThrows() {
        let session = ImprovSession()
        session.loadDemoPiece()
        XCTAssertThrowsError(try session.setPieceTrackInstrument(sectionIndex: 0, trackIndex: 99, instrumentName: "mcb.sf2")) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .invalidPieceTrackIndex)
        }
    }

    func testSetPieceChordInstrumentUpdatesSectionAndLogs() throws {
        let session = ImprovSession()
        session.loadDemoPiece()
        try session.setPieceChordInstrument(sectionIndex: 0, instrumentName: "strings.sf2")
        XCTAssertEqual(session.piece?.sections[0].chordInstrument, "strings.sf2")
        XCTAssertTrue(session.log.contains { $0.contains("strings.sf2") })
    }

    func testSetPieceChordInstrumentWithInvalidSectionIndexThrows() {
        let session = ImprovSession()
        session.loadDemoPiece()
        XCTAssertThrowsError(try session.setPieceChordInstrument(sectionIndex: 99, instrumentName: "strings.sf2")) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .invalidPieceSectionIndex)
        }
    }

    func testPlayWarnsWhenATracksInstrumentFileIsNotFound() throws {
        let session = ImprovSession()
        try session.start()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try session.listSampleFiles(in: folder.path) // lists an empty folder, but sets sampleFolder

        let track = Track(name: "lead", instrument: "does-not-exist.sf2", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60)])
        let section = Section(name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"), tracks: [track])
        try loadTemporaryPiece(Piece(title: "fast", tempoBPM: 6000, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section]), into: session)

        try session.play()

        XCTAssertTrue(session.log.contains { $0.contains("does-not-exist.sf2") && $0.contains("introuvable") })
    }

    func testPlayWithoutAnyTrackInstrumentLogsNoInstrumentWarning() throws {
        let session = ImprovSession()
        try session.start()
        session.loadDemoPiece() // every track/section here has an empty/nil instrument
        try session.play()
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertFalse(session.log.contains { $0.hasPrefix("Instrument:") })
    }

    func testSaveWithoutAPieceLoadedThrows() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.savePiece(toJSONFile: "/dev/null")) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noPieceLoaded)
        }
    }

    func testSaveThenLoadRoundTripsThePieceThroughJSON() throws {
        let session = ImprovSession()
        session.loadDemoPiece()
        let originalTitle = session.piece?.title

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try session.savePiece(toJSONFile: tempFile.path)

        let reloadedSession = ImprovSession()
        try reloadedSession.loadPiece(fromJSONFile: tempFile.path)

        XCTAssertEqual(reloadedSession.piece?.title, originalTitle)
        XCTAssertEqual(reloadedSession.piece, session.piece)
    }

    func testLoadingAMissingFileThrows() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.loadPiece(fromJSONFile: "/no/such/file.json"))
    }

    func testMigratePiecesFindsJSONFilesAndInsertsThem() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = ImprovSession()
        writer.loadDemoPiece()
        try writer.savePiece(toJSONFile: folder.appendingPathComponent("demo.json").path)
        try Data().write(to: folder.appendingPathComponent("notes.txt"))

        let session = makeTestSession()
        session.migratePiecesFromJSONIfNeeded(in: folder.path)
        XCTAssertEqual(session.pieceNames, ["ii-V-I demo"])
    }

    func testUsePieceByIndexAndNameLoadFromTheStore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = ImprovSession()
        writer.loadDemoPiece()
        try writer.savePiece(toJSONFile: folder.appendingPathComponent("demo.json").path)

        let session = makeTestSession()
        session.migratePiecesFromJSONIfNeeded(in: folder.path)
        try session.usePiece(atIndex: 0)
        XCTAssertEqual(session.piece?.title, "ii-V-I demo")

        session.newPiece(title: "Other")
        try session.usePiece(named: "ii-V-I demo")
        XCTAssertEqual(session.piece?.title, "ii-V-I demo")
    }

    func testUsePieceAtInvalidIndexThrows() throws {
        let session = makeTestSession()
        XCTAssertThrowsError(try session.usePiece(atIndex: 0)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .invalidPieceIndex)
        }
    }

    func testSaveWithoutEverLoadingOrSavingThrows() {
        let session = ImprovSession()
        session.loadDemoPiece()
        XCTAssertThrowsError(try session.savePiece()) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noCurrentPieceFile)
        }
    }

    func testSaveAsThenBareSaveUpdateTheSameRecord() throws {
        let session = makeTestSession()
        session.loadDemoPiece()
        try session.savePiece(as: "my-piece")
        XCTAssertEqual(session.pieceNames, ["my-piece"])
        XCTAssertEqual(session.piece?.title, "my-piece", "savePiece(as:) adopts the new name as the piece's own title")

        // A bare `savePiece()` re-saves to that same record without error, and without
        // creating a second one.
        try session.savePiece()
        XCTAssertEqual(session.pieceNames, ["my-piece"])
    }

    func testSaveAsUnderAnExistingTitleOverwritesRatherThanDuplicating() throws {
        let session = makeTestSession()
        session.loadDemoPiece()
        try session.savePiece(as: "my-piece")
        session.newPiece(title: "Different")
        try session.savePiece(as: "my-piece")
        XCTAssertEqual(session.pieceNames, ["my-piece"])
    }

    func testHandlingIncomingMIDIEventsDetectsChordPerTrack() throws {
        let session = ImprovSession()
        // Default fusion mode is now `.individual` (no `.midiMerged` track exists until
        // switched) — this test exercises `.midiMerged` specifically, not the default.
        session.setMIDIFusionMode(.merged)
        // Sound stays off on this track, so this never touches the (unstarted) audio engine.
        try session.startTrack(.midiMerged)
        for pitch in [60, 64, 67, 71] { // C E G B -> Cmaj7
            session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: pitch, velocity: 100, channel: 0), track: .midiMerged)
        }
        let track = session.tracks.first { $0.id == .midiMerged }
        XCTAssertEqual(track?.recognizedChord?.root, PitchClass(0))
        XCTAssertEqual(track?.recognizedChord?.chordTemplateID, "Ma7")
        session.stopTrack(.midiMerged)
        XCTAssertNil(session.tracks.first { $0.id == .midiMerged }?.recognizedChord)
    }

    /// `recentChordEvents` is appended server-side the instant the recognized state changes
    /// (`ImprovSession.recordChordEventIfChanged`), NOT reconstructed by a client polling
    /// `GET /state` — this exercises that log directly through `buildWebConsoleState()` (made
    /// `public` for exactly this), independent of any HTTP/polling layer. Deliberately uses
    /// single notes throughout (not a 3-note chord built one pitch at a time) to keep the
    /// expected event count unambiguous — playing a chord note by note legitimately produces
    /// one event per intermediate held-pitches snapshot (1 note, then 2, then 3), which is the
    /// whole point of this feature (nothing in between gets skipped), not something to work
    /// around here.
    func testRecentChordEventsLogsChangesAndSkipsRestsOnFullRelease() throws {
        let session = ImprovSession()
        session.setMIDIFusionMode(.merged) // default is now .individual; this test needs .midiMerged specifically
        try session.startTrack(.midiMerged)
        func events() -> [WebConsoleChordEvent] {
            session.buildWebConsoleState().tracks.first { $0.id == "midi" }?.recentChordEvents ?? []
        }

        XCTAssertEqual(events().count, 0)

        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0), track: .midiMerged)
        XCTAssertEqual(events().count, 1)
        XCTAssertEqual(events().last?.pitches, [60])

        // A full release must NOT append a blank "rest" entry — the pitch-60 event stays last.
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOff, pitch: 60, velocity: 0, channel: 0), track: .midiMerged)
        XCTAssertEqual(events().count, 1)

        // A different note is a genuinely new, distinct event.
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 62, velocity: 100, channel: 0), track: .midiMerged)
        XCTAssertEqual(events().count, 2)
        XCTAssertEqual(events().last?.pitches, [62])

        // Repeated note-on for an already-held pitch (e.g. a hardware retrigger) is the exact
        // same snapshot again — must not append a duplicate.
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 62, velocity: 100, channel: 0), track: .midiMerged)
        XCTAssertEqual(events().count, 2)

        session.stopTrack(.midiMerged)
        XCTAssertEqual(events().count, 0)
    }

    func testRecentChordEventsCapsAtTwentyEntries() throws {
        let session = ImprovSession()
        session.setMIDIFusionMode(.merged) // default is now .individual; this test needs .midiMerged specifically
        try session.startTrack(.midiMerged)
        func events() -> [WebConsoleChordEvent] {
            session.buildWebConsoleState().tracks.first { $0.id == "midi" }?.recentChordEvents ?? []
        }
        // 25 distinct single-note "events" (each pitch on, then off before the next) — well
        // past the 20-entry cap.
        for pitch in 60..<85 {
            session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: pitch, velocity: 100, channel: 0), track: .midiMerged)
            session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOff, pitch: pitch, velocity: 0, channel: 0), track: .midiMerged)
        }
        XCTAssertEqual(events().count, 20)
        // Oldest entries evicted first — the log should end on the last pitch played (84),
        // not wrap around or drop the most recent one.
        XCTAssertEqual(events().last?.pitches, [84])
        XCTAssertEqual(events().first?.pitches, [65]) // 84 - 20 + 1
    }

    func testStartTrackOnAnUnlistedMIDIPortThrows() {
        let session = ImprovSession()
        // A huge index, not 0: default fusion mode is `.individual`, and a real machine may
        // well have a real MIDI source at index 0 — an index this large guarantees no
        // matching track regardless of how many real MIDI ports happen to be attached.
        XCTAssertThrowsError(try session.startTrack(.midiSource(9999))) { error in
            guard case .unknownTrack = error as? ImprovSession.SessionError else {
                XCTFail("expected .unknownTrack, got \(error)")
                return
            }
        }
    }

    func testDefaultMIDIFusionModeIsIndividual() {
        // See `midiFusionMode`'s own doc comment for why the default is `.individual`, not
        // `.merged` — a per-port track is what lets the LUMI run-mode integration single out
        // the LUMI's own track by name. No MIDI hardware is attached in this environment, so
        // `.midiSource` tracks are simply absent rather than assertable one way or the other.
        let session = ImprovSession()
        XCTAssertEqual(session.midiFusionMode, .individual)
        XCTAssertTrue(session.tracks.contains { $0.id == .computerKeyboard })
        XCTAssertTrue(session.tracks.contains { $0.id == .microphone })
    }

    func testSetMIDIFusionModeSwitchesTrackList() {
        let session = ImprovSession()
        session.setMIDIFusionMode(.individual)
        XCTAssertEqual(session.midiFusionMode, .individual)
        XCTAssertFalse(session.tracks.contains { $0.id == .midiMerged })
        XCTAssertTrue(session.tracks.contains { $0.id == .computerKeyboard })
        XCTAssertTrue(session.tracks.contains { $0.id == .microphone })
    }

    func testComputerKeyboardInputDefaultsOffAndIsToggleable() {
        let session = ImprovSession()
        XCTAssertFalse(session.computerKeyboardInputEnabled)
        session.setComputerKeyboardInputEnabled(true)
        XCTAssertTrue(session.computerKeyboardInputEnabled)
        session.setComputerKeyboardInputEnabled(false)
        XCTAssertFalse(session.computerKeyboardInputEnabled)
    }

    func testRequestComputerKeyboardFocusIncrementsToken() {
        let session = ImprovSession()
        let before = session.computerKeyboardFocusRequestToken
        session.requestComputerKeyboardFocus()
        session.requestComputerKeyboardFocus()
        XCTAssertEqual(session.computerKeyboardFocusRequestToken, before + 2)
    }

    func testShiftComputerKeyboardOctaveAppliesTwelveSemitonesPerStep() {
        let session = ImprovSession()
        XCTAssertEqual(session.computerKeyboardOctaveShift, 0)
        session.shiftComputerKeyboardOctave(by: 1)
        XCTAssertEqual(session.computerKeyboardOctaveShift, 12)
        session.shiftComputerKeyboardOctave(by: -2)
        XCTAssertEqual(session.computerKeyboardOctaveShift, -12)
    }

    func testMicrophoneTrackCannotHaveSound() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.setSoundEnabled(true, for: .microphone)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .trackCannotHaveSound)
        }
    }

    func testSetMicrophoneRecognitionModeRejectsNonMicrophoneTrack() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.setMicrophoneRecognitionMode(.monophonicHPS, for: .computerKeyboard)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .recognitionModeOnlyForMicrophone)
        }
    }

    func testSetMicrophoneRecognitionModeRejectsInvalidWindowCount() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.setMicrophoneRecognitionMode(.polyphonicLatched(windows: 0), for: .microphone)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .invalidRecognitionWindowCount)
        }
        XCTAssertThrowsError(try session.setMicrophoneRecognitionMode(.polyphonicSliding(windows: 0), for: .microphone)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .invalidRecognitionWindowCount)
        }
    }

    func testSetMicrophoneRecognitionModeSurvivesTrackRestart() throws {
        let session = ImprovSession()
        try session.setMicrophoneRecognitionMode(.monophonicHPS, for: .microphone)
        try session.startTrack(.microphone)
        XCTAssertEqual(session.tracks.first { $0.id == .microphone }?.microphoneRecognitionMode, .monophonicHPS)
        // Changing mode while listening restarts the track — should still end up listening,
        // now under the new mode.
        try session.setMicrophoneRecognitionMode(.polyphonicSliding(windows: 4), for: .microphone)
        let track = session.tracks.first { $0.id == .microphone }
        XCTAssertEqual(track?.microphoneRecognitionMode, .polyphonicSliding(windows: 4))
        XCTAssertEqual(track?.isListening, true)
    }

    func testMicrophonePolyLatchedDoesNotConfirmAFlickeringNote() throws {
        let session = ImprovSession()
        try session.setMicrophoneRecognitionMode(.polyphonicLatched(windows: 3), for: .microphone)
        try session.startTrack(.microphone)
        let pitch = DetectedPitch(frequencyHz: 261.63, midiPitch: 60)
        session.simulateMicrophoneDetection([pitch], level: 0.1, track: .microphone)
        session.simulateMicrophoneDetection([], level: 0.1, track: .microphone)
        session.simulateMicrophoneDetection([pitch], level: 0.1, track: .microphone)
        XCTAssertFalse(session.tracks.first { $0.id == .microphone }!.heldPitches.contains(60))
    }

    func testMicrophonePolySlidingConfirmsUnderMajorityDespiteOneDropout() throws {
        let session = ImprovSession()
        try session.setMicrophoneRecognitionMode(.polyphonicSliding(windows: 3), for: .microphone)
        try session.startTrack(.microphone)
        let pitch = DetectedPitch(frequencyHz: 261.63, midiPitch: 60)
        session.simulateMicrophoneDetection([pitch], level: 0.1, track: .microphone)
        session.simulateMicrophoneDetection([], level: 0.1, track: .microphone)
        session.simulateMicrophoneDetection([pitch], level: 0.1, track: .microphone)
        XCTAssertTrue(session.tracks.first { $0.id == .microphone }!.heldPitches.contains(60))
    }

    func testMicrophoneMonophonicModeConfirmsImmediately() throws {
        let session = ImprovSession()
        try session.setMicrophoneRecognitionMode(.monophonicHeuristic, for: .microphone)
        try session.startTrack(.microphone)
        let pitch = DetectedPitch(frequencyHz: 261.63, midiPitch: 60)
        session.simulateMicrophoneDetection([pitch], level: 0.1, track: .microphone)
        XCTAssertTrue(session.tracks.first { $0.id == .microphone }!.heldPitches.contains(60))
    }

    func testMicrophoneCalibrationCapturesThePeakLevelForTheQuietPhase() throws {
        let session = makeTestSession()
        try session.startTrack(.microphone)
        session.beginMicrophoneCalibrationCapture(phase: .quiet)
        session.simulateMicrophoneDetection([], level: 0.01, track: .microphone)
        session.simulateMicrophoneDetection([], level: 0.05, track: .microphone) // peak
        session.simulateMicrophoneDetection([], level: 0.02, track: .microphone) // lower again
        try session.endMicrophoneCalibrationCapture()
        XCTAssertEqual(session.microphoneCalibration.quietRMS, 0.05)
    }

    func testMicrophoneCalibrationCapturesThePeakLevelForTheLoudPhase() throws {
        let session = makeTestSession()
        try session.startTrack(.microphone)
        session.beginMicrophoneCalibrationCapture(phase: .loud)
        session.simulateMicrophoneDetection([], level: 0.2, track: .microphone)
        session.simulateMicrophoneDetection([], level: 0.4, track: .microphone) // peak
        try session.endMicrophoneCalibrationCapture()
        XCTAssertEqual(session.microphoneCalibration.loudRMS, 0.4)
    }

    func testCancellingMicrophoneCalibrationCaptureLeavesSettingsUnchanged() throws {
        let session = makeTestSession()
        try session.startTrack(.microphone)
        let before = session.microphoneCalibration
        session.beginMicrophoneCalibrationCapture(phase: .loud)
        session.simulateMicrophoneDetection([], level: 0.9, track: .microphone)
        session.cancelMicrophoneCalibrationCapture()
        try session.endMicrophoneCalibrationCapture() // no capture in progress: a no-op
        XCTAssertEqual(session.microphoneCalibration, before)
    }

    func testResetMicrophoneCalibrationRestoresDefaults() throws {
        let session = makeTestSession()
        try session.startTrack(.microphone)
        session.beginMicrophoneCalibrationCapture(phase: .loud)
        session.simulateMicrophoneDetection([], level: 0.9, track: .microphone)
        try session.endMicrophoneCalibrationCapture()
        XCTAssertNotEqual(session.microphoneCalibration, MicrophoneCalibrationSettingsFile())
        try session.resetMicrophoneCalibration()
        XCTAssertEqual(session.microphoneCalibration, MicrophoneCalibrationSettingsFile())
    }

    // Note: no test exercises `storeMicrophoneSpectrum`'s opportunistic peak-magnitude capture
    // end-to-end via real microphone hardware — an earlier attempt was inherently flaky (it
    // depends on real ambient room noise clearing `minimumRMSForDetection` within the test's
    // sleep window, which no sleep duration can guarantee) and removed. The preference logic
    // (exact capture wins when > 0, else a real RMS-to-magnitude conversion) is covered
    // deterministically by `testEstimatedPeakMagnitudePrefersExactCaptureOverRMSConversion`
    // below; the "off" path is covered by the test immediately below.

    func testMicrophoneCalibrationLeavesPeakSpectrumMagnitudeAtZeroWhenSpectroscopeIsOff() throws {
        let session = makeTestSession()
        try session.startTrack(.microphone)
        // Spectroscope left off (the default) — no spectrum data ever flows, so there's
        // nothing to capture a peak magnitude from.
        session.beginMicrophoneCalibrationCapture(phase: .quiet)
        session.simulateMicrophoneDetection([], level: 0.02, track: .microphone)
        try session.endMicrophoneCalibrationCapture()
        XCTAssertEqual(session.microphoneCalibration.quietPeakMagnitude, 0)
    }

    func testMicrophoneCalibrationSettingsFileDecodesOldJSONWithoutPeakMagnitudeFields() throws {
        let oldJSON = #"{"quietRMS": 0.01, "loudRMS": 0.2}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MicrophoneCalibrationSettingsFile.self, from: oldJSON)
        XCTAssertEqual(decoded.quietRMS, 0.01)
        XCTAssertEqual(decoded.loudRMS, 0.2)
        XCTAssertEqual(decoded.quietPeakMagnitude, 0)
        XCTAssertEqual(decoded.loudPeakMagnitude, 0)
    }

    func testEstimatedPeakMagnitudePrefersExactCaptureOverRMSConversion() {
        var calibration = MicrophoneCalibrationSettingsFile(loudRMS: 0.3, loudPeakMagnitude: 123456)
        XCTAssertEqual(calibration.estimatedLoudPeakMagnitude, 123456)
        calibration.loudPeakMagnitude = 0 // never captured with spectrum data
        // Falls back to a real RMS-to-magnitude conversion, not zero or a live-frame value.
        let expected = Float(Double(calibration.loudRMS) * Double(calibration.loudRMS) * FFTPitchAnalyzer.approximatePeakPowerPerSquaredRMS)
        XCTAssertEqual(calibration.estimatedLoudPeakMagnitude, expected)
        XCTAssertGreaterThan(calibration.estimatedLoudPeakMagnitude, 0)
    }

    func testMicrophoneCalibrationNormalizedMapsQuietLoudRangeAndRejectsADegenerateRange() {
        let calibration = MicrophoneCalibrationSettingsFile(quietRMS: 0.01, loudRMS: 0.11)
        XCTAssertEqual(calibration.normalized(0.01), 0)
        XCTAssertEqual(calibration.normalized(0.11), 1)
        XCTAssertEqual(calibration.normalized(0.06) ?? -1, Float(0.5), accuracy: 0.0001)
        XCTAssertEqual(calibration.normalized(-1), 0) // clamped below quiet
        XCTAssertEqual(calibration.normalized(5), 1) // clamped above loud
        XCTAssertNil(MicrophoneCalibrationSettingsFile(quietRMS: 0.2, loudRMS: 0.1).normalized(0.15))
    }

    func testEnablingSoundOnATrackSoundsIncomingNotes() throws {
        let session = ImprovSession()
        try session.start() // needed before the track's own sampler is exercised below
        try session.startTrack(.computerKeyboard)
        try session.setSoundEnabled(true, for: .computerKeyboard)
        // Just verifying this doesn't throw/crash when routed to the (now-started) sampler.
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
    }

    // MARK: - Composition (new piece, source text, LLM connections)

    func testNewPieceStartsBlank() {
        let session = ImprovSession()
        session.newPiece(title: "My Poem Piece")
        XCTAssertEqual(session.piece?.title, "My Poem Piece")
        XCTAssertEqual(session.piece?.sections, [])
        XCTAssertNil(session.currentPieceRecordID)
    }

    func testSetSourceTextStoresItAndLogs() {
        let session = ImprovSession()
        session.setSourceText("Roses are red")
        XCTAssertEqual(session.sourceText, "Roses are red")
        XCTAssertTrue(session.log.contains { $0.contains("Source text set") })
    }

    func testMigrateLLMConnectionsFindsJSONFilesAndInsertsThem() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let connection = LLMConnection(name: "Local Ollama", provider: "ollama", baseURL: "http://localhost:11434", model: "llama3")
        try JSONEncoder().encode(connection).write(to: folder.appendingPathComponent("ollama.json"))
        try Data().write(to: folder.appendingPathComponent("notes.txt"))

        let session = makeTestSession()
        session.migrateLLMConnectionsFromJSONIfNeeded(in: folder.path)
        XCTAssertEqual(session.llmConnections, ["Local Ollama"])
    }

    func testMigrateLLMConnectionsSeedsBuiltInTemplatesWhenNothingToMigrate() throws {
        let emptyFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyFolder) }

        let session = makeTestSession()
        session.migrateLLMConnectionsFromJSONIfNeeded(in: emptyFolder.path)
        XCTAssertEqual(session.llmConnections.count, LLMConnectionTemplates.builtIn.count)
        XCTAssertTrue(session.llmConnections.contains("Ollama (local)"))
    }

    func testMigrateLLMConnectionsIsIdempotent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let connection = LLMConnection(name: "Local Ollama", provider: "ollama", baseURL: "http://localhost:11434", model: "llama3")
        try JSONEncoder().encode(connection).write(to: folder.appendingPathComponent("ollama.json"))

        let session = makeTestSession()
        session.migrateLLMConnectionsFromJSONIfNeeded(in: folder.path)
        session.migrateLLMConnectionsFromJSONIfNeeded(in: folder.path)
        XCTAssertEqual(session.llmConnections, ["Local Ollama"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("ollama.json").path), "the original file must survive migration")
    }

    func testAddAndDeleteLLMConnection() throws {
        let session = makeTestSession()
        let connection = LLMConnection(name: "Custom", provider: "ollama", baseURL: "http://localhost:11434", model: "llama3")
        try session.addLLMConnection(connection)
        XCTAssertEqual(session.llmConnections, ["Custom"])

        try session.deleteLLMConnection(atIndex: 0)
        XCTAssertEqual(session.llmConnections, [])
    }

    func testUseLLMConnectionByIndexAndNameLoadFromTheStore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let connection = LLMConnection(name: "Local Ollama", provider: "ollama", baseURL: "http://localhost:11434", model: "llama3")
        try JSONEncoder().encode(connection).write(to: folder.appendingPathComponent("ollama.json"))

        let session = makeTestSession()
        session.migrateLLMConnectionsFromJSONIfNeeded(in: folder.path)
        try session.useLLMConnection(atIndex: 0)
        XCTAssertEqual(session.currentLLMConnection, connection)

        let byName = makeTestSession()
        byName.migrateLLMConnectionsFromJSONIfNeeded(in: folder.path)
        try byName.useLLMConnection(named: "Local Ollama")
        XCTAssertEqual(byName.currentLLMConnection, connection)
    }

    func testComposeFromTextWithoutSourceTextThrows() throws {
        let session = makeTestSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "x", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("x.json"))
        session.migrateLLMConnectionsFromJSONIfNeeded(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        XCTAssertThrowsError(try session.composeFromText()) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noSourceText)
        }
    }

    func testComposeFromTextWithoutAConnectionThrows() {
        let session = ImprovSession()
        session.setSourceText("a poem")
        XCTAssertThrowsError(try session.composeFromText()) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noLLMConnectionSelected)
        }
    }

    func testComposeFromTextWithAFakeGeneratorProducesAValidatedPiece() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = makeTestSession()
        session.setSourceText("a poem about the sea")
        session.migrateLLMConnectionsFromJSONIfNeeded(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        let fakeResponse = """
        { "title": "The Sea", "tempoBPM": 80, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        try session.composeFromText { prompt, connection in
            XCTAssertTrue(prompt.contains("a poem about the sea"))
            XCTAssertEqual(connection.name, "Fake")
            return fakeResponse
        }

        XCTAssertEqual(session.piece?.title, "The Sea")
        XCTAssertNil(session.currentPieceRecordID)
    }

    func testComposeFromTextWithATitleOverridesTheLLMsOwnTitle() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = makeTestSession()
        session.setSourceText("a poem about the sea")
        session.migrateLLMConnectionsFromJSONIfNeeded(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        let fakeResponse = """
        { "title": "LLM Chosen Title", "tempoBPM": 80, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        try session.composeFromText(title: "My Own Title") { _, _ in fakeResponse }

        XCTAssertEqual(session.piece?.title, "My Own Title")
    }

    func testSetAdditionalCompositionInstructionsAreIncludedInThePrompt() throws {
        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        session.setAdditionalCompositionInstructions("romantique, mode mineur")

        let prompt = try session.currentTextCompositionPrompt()

        XCTAssertTrue(prompt.contains("romantique, mode mineur"))
        XCTAssertTrue(prompt.contains("a poem about the sea"))
    }

    func testSetAdditionalCompositionInstructionsEmptyStringClearsThem() {
        let session = ImprovSession()
        session.setAdditionalCompositionInstructions("romantique")
        XCTAssertEqual(session.additionalCompositionInstructions, "romantique")
        session.setAdditionalCompositionInstructions("")
        XCTAssertNil(session.additionalCompositionInstructions)
    }

    func testSetCompositionTitleEmptyStringClearsIt() {
        let session = ImprovSession()
        session.setCompositionTitle("Ma Ballade")
        XCTAssertEqual(session.compositionTitle, "Ma Ballade")
        session.setCompositionTitle("")
        XCTAssertNil(session.compositionTitle)
        session.setCompositionTitle(nil)
        XCTAssertNil(session.compositionTitle)
    }

    func testComposeFromTextSendsAdditionalInstructionsInThePrompt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = makeTestSession()
        session.setSourceText("a poem about the sea")
        session.setAdditionalCompositionInstructions("romantique, mode mineur")
        session.migrateLLMConnectionsFromJSONIfNeeded(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        let fakeResponse = """
        { "title": "The Sea", "tempoBPM": 80, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        try session.composeFromText { prompt, _ in
            XCTAssertTrue(prompt.contains("romantique, mode mineur"))
            return fakeResponse
        }
    }

    func testComposeFromTextWithInvalidResponseThrowsWithWarnings() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = makeTestSession()
        session.setSourceText("a poem")
        session.migrateLLMConnectionsFromJSONIfNeeded(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        XCTAssertThrowsError(try session.composeFromText { _, _ in "not json at all" }) { error in
            guard case .llmComposeFailed = error as? ImprovSession.SessionError else {
                XCTFail("expected .llmComposeFailed, got \(error)")
                return
            }
        }
        XCTAssertNil(session.piece)
    }

    // MARK: - Recording (SoundTrack — purely event-based, real seconds)

    func testRecordingCapturesFilteredTrackEvents() throws {
        let session = ImprovSession()
        try session.startTrack(.computerKeyboard)
        try session.startTrack(.microphone)
        try session.startRecording(title: "Test", tracks: [.computerKeyboard])
        session.pressKey(pitch: 60, track: .computerKeyboard) // should be captured
        session.pressKey(pitch: 64, track: .microphone) // filtered out, should not be captured
        Thread.sleep(forTimeInterval: 0.05)
        let soundTrack = try session.stopRecording()
        XCTAssertEqual(soundTrack.events.count, 1)
        XCTAssertEqual(soundTrack.events.first?.trackID, "clavier")
        XCTAssertEqual(soundTrack.events.first?.pitch, 60)
    }

    func testStartRecordingTwiceThrows() throws {
        let session = ImprovSession()
        try session.startRecording(title: "A")
        XCTAssertThrowsError(try session.startRecording(title: "B")) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .alreadyRecording)
        }
    }

    func testStopRecordingWithoutStartingThrows() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.stopRecording()) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .notRecording)
        }
    }

    func testSoundTrackSaveThenLoadRoundTrips() throws {
        let session = ImprovSession()
        try session.startRecording(title: "RoundTrip")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveSoundTrack(toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.loadSoundTrack(fromJSONFile: tempFile.path)
        XCTAssertEqual(reloaded.currentSoundTrack?.events.count, session.currentSoundTrack?.events.count)
    }

    // MARK: - SoundTrack: store-based CRUD (see SoundTrackRecord)

    func testMigrateSoundTracksFindsJSONFilesAndInsertsThem() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let soundTrack = SoundTrack(title: "Practice", durationSeconds: 1, events: [])
        try JSONEncoder().encode(soundTrack).write(to: folder.appendingPathComponent("practice.json"))

        let session = makeTestSession()
        session.migrateSoundTracksFromJSONIfNeeded(in: folder.path)
        XCTAssertEqual(session.soundTrackNames, ["Practice"])
    }

    func testMigrateSoundTracksIsIdempotent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let soundTrack = SoundTrack(title: "Practice", durationSeconds: 1, events: [])
        try JSONEncoder().encode(soundTrack).write(to: folder.appendingPathComponent("practice.json"))

        let session = makeTestSession()
        session.migrateSoundTracksFromJSONIfNeeded(in: folder.path)
        session.migrateSoundTracksFromJSONIfNeeded(in: folder.path)
        XCTAssertEqual(session.soundTrackNames, ["Practice"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("practice.json").path), "the original file must survive migration")
    }

    func testSaveSoundTrackAsCreatesThenOverwritesOnSameTitle() throws {
        let session = makeTestSession()
        try session.startRecording(title: "Draft")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()
        try session.saveSoundTrack(as: "Final")
        XCTAssertEqual(session.soundTrackNames, ["Final"])
        XCTAssertEqual(session.currentSoundTrack?.title, "Final")
        XCTAssertEqual(session.currentSoundTrack?.events.count, 2)

        try session.startRecording(title: "Draft2")
        session.pressKey(pitch: 62)
        session.releaseKey(pitch: 62)
        session.pressKey(pitch: 64)
        session.releaseKey(pitch: 64)
        _ = try session.stopRecording() // sets currentSoundTrack to the second take
        try session.saveSoundTrack(as: "Final")
        XCTAssertEqual(session.soundTrackNames, ["Final"], "saving under an existing title overwrites it rather than duplicating")
        try session.useSoundTrack(named: "Final")
        XCTAssertEqual(session.currentSoundTrack?.events.count, 4, "the overwrite captured the second take")
    }

    func testUseSoundTrackByIndexAndNameLoadFromTheStore() throws {
        let session = makeTestSession()
        try session.startRecording(title: "Practice")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()
        try session.saveSoundTrack(as: "Practice")

        try session.startRecording(title: "Other")
        _ = try session.stopRecording()

        try session.useSoundTrack(atIndex: 0)
        XCTAssertEqual(session.currentSoundTrack?.title, "Practice")

        try session.startRecording(title: "Other")
        _ = try session.stopRecording()
        try session.useSoundTrack(named: "Practice")
        XCTAssertEqual(session.currentSoundTrack?.title, "Practice")
    }

    func testDeleteSoundTrackRemovesItFromTheStore() throws {
        let session = makeTestSession()
        try session.startRecording(title: "Practice")
        _ = try session.stopRecording()
        try session.saveSoundTrack(as: "Practice")
        XCTAssertEqual(session.soundTrackNames, ["Practice"])

        try session.deleteSoundTrack(atIndex: 0)
        XCTAssertEqual(session.soundTrackNames, [])
    }

    func testPlaySoundTrackTracksPlaybackStateThenClearsItWhenFinished() throws {
        let session = ImprovSession()
        try session.start()
        try session.startRecording(title: "Play")
        session.pressKey(pitch: 60)
        Thread.sleep(forTimeInterval: 0.05)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()

        try session.playSoundTrack()
        XCTAssertTrue(session.isPlayingSoundTrack)

        Thread.sleep(forTimeInterval: (session.currentSoundTrack?.durationSeconds ?? 0) + 0.4)
        XCTAssertFalse(session.isPlayingSoundTrack)
        XCTAssertTrue(session.soundTrackHeldPitches.isEmpty)
    }

    func testPlaySoundTrackWithoutARecordingThrows() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.playSoundTrack()) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noSoundTrackRecorded)
        }
    }

    func testComposeSoundTrackToPiecesWithAFakeGeneratorProducesValidatedPieces() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = makeTestSession()
        session.migrateLLMConnectionsFromJSONIfNeeded(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        try session.startRecording(title: "ForCompose")
        session.pressKey(pitch: 62)
        session.releaseKey(pitch: 62)
        _ = try session.stopRecording()

        let fakeResponse = """
        { "title": "From Recording", "tempoBPM": 90, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        let labels = try session.composeSoundTrackToPieces(candidateCount: 1) { prompt, connection in
            XCTAssertTrue(prompt.contains("ON"))
            XCTAssertEqual(connection.name, "Fake")
            return fakeResponse
        }
        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(session.piece?.title, "From Recording")
        XCTAssertEqual(session.pieceNames, ["From Recording"])
    }

    func testComposeSoundTrackToPiecesWithATitleOverridesTheLLMsOwnTitle() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = makeTestSession()
        session.migrateLLMConnectionsFromJSONIfNeeded(in: folder.path)
        try session.useLLMConnection(atIndex: 0)
        try session.startRecording(title: "ForCompose")
        session.pressKey(pitch: 62)
        session.releaseKey(pitch: 62)
        _ = try session.stopRecording()

        let fakeResponse = """
        { "title": "LLM Chosen Title", "tempoBPM": 90, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        let labels = try session.composeSoundTrackToPieces(candidateCount: 1, title: "My Own Title") { _, _ in fakeResponse }

        XCTAssertEqual(session.piece?.title, "My Own Title")
        XCTAssertEqual(labels[0], "My Own Title")
    }

    // MARK: - Composition prompts (preview, save/load)

    func testCurrentTextCompositionPromptWithoutSourceTextOrOverrideThrows() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.currentTextCompositionPrompt()) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noSourceText)
        }
    }

    func testCurrentTextCompositionPromptBuildsFromSourceText() throws {
        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        let prompt = try session.currentTextCompositionPrompt()
        XCTAssertTrue(prompt.contains("a poem about the sea"))
    }

    func testCurrentSoundTrackCompositionPromptWithoutARecordingOrOverrideThrows() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.currentSoundTrackCompositionPrompt()) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noSoundTrackRecorded)
        }
    }

    func testSetPromptsFolderCreatesAllFiveSubfoldersAndListsFiles() throws {
        let session = makeTestSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        try session.setPromptsFolder(root.path)

        var isDirectory: ObjCBool = false
        for subfolder in ["Cadrage Composition Descriptive", "Cadrage Composition Soundtrack", "composition Descriptive", "Indications Soundtracks", "Export"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(subfolder).path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
        }
        XCTAssertEqual(session.textFramingSentenceNames, [])
        XCTAssertEqual(session.soundTrackFramingSentenceNames, [])
        XCTAssertEqual(session.soundTrackInstructionsNames, [])
        XCTAssertEqual(session.compositionDescriptionNames, [])
    }

    func testExportTextCompositionPromptWritesCurrentPromptToExportSubfolder() throws {
        let session = makeTestSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        session.setSourceText("a poem about the sea")

        try session.exportTextCompositionPrompt(as: "my-export")
        let exported = try String(contentsOf: root.appendingPathComponent("Export/my-export.txt"), encoding: .utf8)
        XCTAssertEqual(exported, try session.currentTextCompositionPrompt())
        XCTAssertTrue(exported.contains("a poem about the sea"))
    }

    func testExportSoundTrackCompositionPromptWritesCurrentPromptToExportSubfolder() throws {
        let session = makeTestSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        try session.startRecording(title: "ForExport")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()

        try session.exportSoundTrackCompositionPrompt(as: "my-soundtrack-export")
        let exported = try String(contentsOf: root.appendingPathComponent("Export/my-soundtrack-export.txt"), encoding: .utf8)
        XCTAssertEqual(exported, try session.currentSoundTrackCompositionPrompt())
    }

    func testSaveAndUseSoundTrackCompositionInstructionsRoundTrips() throws {
        let session = makeTestSession()
        XCTAssertNil(session.currentSoundTrackCompositionInstructions())

        session.setSoundTrackCompositionInstructions("romantique, mode mineur")
        try session.saveSoundTrackCompositionInstructions(as: "my-instructions")
        XCTAssertEqual(session.soundTrackInstructionsNames, ["my-instructions"])

        session.resetSoundTrackCompositionInstructions()
        XCTAssertNil(session.currentSoundTrackCompositionInstructions())

        try session.useSoundTrackCompositionInstructions(atIndex: 0)
        XCTAssertEqual(session.activeSoundTrackCompositionInstructions, "romantique, mode mineur")
    }

    func testSaveSoundTrackCompositionInstructionsWithoutAnySetThrows() throws {
        let session = makeTestSession()
        XCTAssertThrowsError(try session.saveSoundTrackCompositionInstructions(as: "nothing-to-save")) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noSoundTrackCompositionInstructions)
        }
    }

    func testUseSoundTrackCompositionInstructionsWithInvalidIndexThrows() throws {
        let session = makeTestSession()
        XCTAssertThrowsError(try session.useSoundTrackCompositionInstructions(atIndex: 0)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .invalidSoundTrackInstructionsIndex)
        }
    }

    func testCurrentSoundTrackCompositionPromptIncludesActiveInstructions() throws {
        let session = ImprovSession()
        try session.startRecording(title: "ForInstructions")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()
        session.setSoundTrackCompositionInstructions("romantique, mode mineur")
        let prompt = try session.currentSoundTrackCompositionPrompt()
        XCTAssertTrue(prompt.contains("romantique, mode mineur"))
    }

    // MARK: - Framing sentence (the part of the prompt before the JSON schema)

    func testCurrentFramingSentenceDefaultsToTheBuiltInConstants() {
        let session = ImprovSession()
        XCTAssertEqual(session.currentTextFramingSentence(), LLMPieceComposer.defaultTextFramingSentence)
        XCTAssertEqual(session.currentSoundTrackFramingSentence(), LLMPieceComposer.defaultSoundTrackFramingSentence)
    }

    func testSetTextFramingSentenceIsReflectedInTheFullPrompt() throws {
        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        session.setTextFramingSentence("Custom framing sentence.")
        XCTAssertEqual(session.currentTextFramingSentence(), "Custom framing sentence.")
        XCTAssertTrue((try session.currentTextCompositionPrompt()).contains("Custom framing sentence."))
    }

    func testSetTextFramingSentenceEmptyStringRevertsToDefault() {
        let session = ImprovSession()
        session.setTextFramingSentence("Custom.")
        XCTAssertEqual(session.currentTextFramingSentence(), "Custom.")
        session.setTextFramingSentence("")
        XCTAssertEqual(session.currentTextFramingSentence(), LLMPieceComposer.defaultTextFramingSentence)
    }

    func testSaveAndUseTextFramingSentenceRoundTrips() throws {
        let session = makeTestSession()
        session.setTextFramingSentence("A distinctive custom framing sentence.")

        try session.saveTextFramingSentence(as: "my-framing")
        XCTAssertEqual(session.textFramingSentenceNames, ["my-framing"])

        session.resetTextFramingSentence()
        XCTAssertEqual(session.currentTextFramingSentence(), LLMPieceComposer.defaultTextFramingSentence)

        try session.useTextFramingSentence(atIndex: 0)
        XCTAssertEqual(session.activeTextFramingSentence, "A distinctive custom framing sentence.")
    }

    func testSaveAndUseSoundTrackFramingSentenceRoundTrips() throws {
        let session = makeTestSession()
        session.setSoundTrackFramingSentence("A distinctive soundtrack framing sentence.")

        try session.saveSoundTrackFramingSentence(as: "my-soundtrack-framing")
        XCTAssertEqual(session.soundTrackFramingSentenceNames, ["my-soundtrack-framing"])

        session.resetSoundTrackFramingSentence()
        try session.useSoundTrackFramingSentence(named: "my-soundtrack-framing")
        XCTAssertEqual(session.activeSoundTrackFramingSentence, "A distinctive soundtrack framing sentence.")
    }

    func testUseTextFramingSentenceWithInvalidIndexThrows() throws {
        let session = makeTestSession()
        XCTAssertThrowsError(try session.useTextFramingSentence(atIndex: 0)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .invalidTextFramingIndex)
        }
    }

    // MARK: - Composition descriptions (save/load title+text+indications)

    func testSaveThenLoadCompositionDescriptionRoundTrips() throws {
        let session = makeTestSession()
        session.setCompositionTitle("My Ballad")
        session.setSourceText("a poem about the sea")
        session.setAdditionalCompositionInstructions("romantique, mode mineur")
        try session.saveCompositionDescription(as: "my-description")
        XCTAssertEqual(session.compositionDescriptionNames, ["my-description"])

        session.setCompositionTitle("Other")
        session.setSourceText("something else")
        try session.useCompositionDescription(atIndex: 0)
        XCTAssertEqual(session.compositionTitle, "My Ballad")
        XCTAssertEqual(session.sourceText, "a poem about the sea")
        XCTAssertEqual(session.additionalCompositionInstructions, "romantique, mode mineur")
    }

    func testLoadCompositionDescriptionAtInvalidIndexThrows() throws {
        let session = makeTestSession()
        XCTAssertThrowsError(try session.useCompositionDescription(atIndex: 0)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .invalidCompositionIndex)
        }
    }

    func testSaveCompositionDescriptionWithoutSourceTextThrows() {
        let session = makeTestSession()
        XCTAssertThrowsError(try session.saveCompositionDescription(as: "whatever")) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noSourceText)
        }
    }

    func testSaveCompositionDescriptionWithoutHavingSavedOnceThrows() {
        let session = makeTestSession()
        session.setSourceText("a poem")
        XCTAssertThrowsError(try session.saveCompositionDescription()) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noCurrentCompositionFile)
        }
    }

    func testSaveCompositionDescriptionReSavesToTheSameRecord() throws {
        let session = makeTestSession()
        session.setSourceText("first version")
        try session.saveCompositionDescription(as: "iterate")

        session.setSourceText("second version")
        try session.saveCompositionDescription()

        try session.useCompositionDescription(named: "iterate")
        XCTAssertEqual(session.sourceText, "second version")
        XCTAssertEqual(session.compositionDescriptionNames, ["iterate"], "re-saving must not create a second record")
    }

    // Port 18391 is arbitrary, chosen only to avoid colliding with the collaborative-session
    // test's own fixed port — same "rerun failing with 'address already in use' means the OS
    // hasn't released it yet, not a logic bug" caveat applies here too.
    func testStartWebConsoleSetsPortAndStopClearsIt() throws {
        let session = ImprovSession()
        XCTAssertNil(session.webConsolePort)
        try session.startWebConsole(port: 18391)
        XCTAssertEqual(session.webConsolePort, 18391)
        session.stopWebConsole()
        XCTAssertNil(session.webConsolePort)
    }

    func testStartWebConsoleTwiceThrows() throws {
        let session = ImprovSession()
        try session.startWebConsole(port: 18392)
        defer { session.stopWebConsole() }
        XCTAssertThrowsError(try session.startWebConsole(port: 18393)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .webConsoleAlreadyActive)
        }
    }

    func testStartWebConsoleInvalidPortThrows() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.startWebConsole(port: 999_999))
        XCTAssertNil(session.webConsolePort)
    }

    func testStopWebConsoleWithoutStartingIsANoOp() {
        let session = ImprovSession()
        session.stopWebConsole() // must not crash/throw
        XCTAssertNil(session.webConsolePort)
    }

    func testBuildPieceDetailReflectsWholeStructureIncludingEmptyTracks() throws {
        let session = ImprovSession()
        XCTAssertFalse(session.buildPieceDetail().loaded)

        let trackWithNotes = Track(name: "lead", instrument: "mcb.sf2", melodyEvents: [
            MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60),
        ])
        // The real regression this route fixes: `pieceDetailLines()` (the terminal's own
        // piece display) silently skips any track with zero `melodyEvents` — a fragment-only
        // track just vanishes. `buildPieceDetail()` must not repeat that mistake.
        let emptyTrack = Track(name: "fragment-only", instrument: "")
        let chord = ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma7"))
        let section = Section(
            name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
            chordProgression: [chord], tracks: [trackWithNotes, emptyTrack]
        )
        try loadTemporaryPiece(
            Piece(title: "Detail Test", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section]),
            into: session
        )

        let detail = session.buildPieceDetail()
        XCTAssertTrue(detail.loaded)
        XCTAssertEqual(detail.sections?.count, 1)
        XCTAssertEqual(detail.sections?[0].chordProgression.first?.chord.label, "CMa7")
        XCTAssertEqual(detail.sections?[0].tracks.count, 2)
        XCTAssertTrue(detail.sections?[0].tracks.contains { $0.name == "fragment-only" && $0.melodyEvents.isEmpty } ?? false)
    }

    func testBuildCompositionDetailReflectsStagedTextAndResolvedPrompt() {
        let session = ImprovSession()
        let empty = session.buildCompositionDetail()
        XCTAssertNil(empty.sourceText)
        XCTAssertNil(empty.resolvedPrompt)

        session.setSourceText("a quiet lake at dusk")
        session.setCompositionTitle("Lake Piece")
        session.setAdditionalCompositionInstructions("impressionist, slow tempo")

        let detail = session.buildCompositionDetail()
        XCTAssertEqual(detail.title, "Lake Piece")
        XCTAssertEqual(detail.sourceText, "a quiet lake at dusk")
        XCTAssertEqual(detail.additionalInstructions, "impressionist, slow tempo")
        XCTAssertTrue(detail.resolvedPrompt?.contains("a quiet lake at dusk") ?? false)
    }

    func testBuildGuideDetailReflectsAllStepsNotJustCurrent() throws {
        let session = ImprovSession()
        XCTAssertFalse(session.buildGuideDetail().loaded)

        session.newGuideSequence(title: "Explore")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.addGuideStep(ModeReference(tonic: 7, scaleID: "mixolydian"))
        try session.startGuide()

        let detail = session.buildGuideDetail()
        XCTAssertTrue(detail.loaded)
        XCTAssertEqual(detail.title, "Explore")
        XCTAssertEqual(detail.steps?.count, 2)
        XCTAssertEqual(detail.currentStepIndex, 0)
        XCTAssertTrue(detail.steps?[0].isCurrent ?? false)
        // The real regression this route fixes: `GET /state`'s own `guide` field only ever
        // exposes the CURRENT step's mode/chords — a non-current step's own detail must
        // still be reported here.
        XCTAssertFalse(detail.steps?[1].isCurrent ?? true)
        XCTAssertEqual(detail.steps?[1].mode.scaleID, "mixolydian")
        XCTAssertEqual(detail.steps?[1].mode.tonicName, "G")
    }

    func testAdvanceGuideChordNavigatesWithinAndAcrossSteps() throws {
        let session = ImprovSession()
        session.newGuideSequence(title: "Chord Nav Test")
        // Step 0: 2 chords. Step 1: no chord progression at all (must be skipped through
        // entirely). Step 2: 2 chords.
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"), chordProgression: ChordProgressionTemplate(name: "step0", degrees: ["I", "V"]))
        try session.addGuideStep(ModeReference(tonic: 2, scaleID: "dorian"))
        try session.addGuideStep(ModeReference(tonic: 7, scaleID: "mixolydian"), chordProgression: ChordProgressionTemplate(name: "step2", degrees: ["I", "IV"]))
        try session.startGuide()

        XCTAssertNil(session.currentGuideChordIndex)

        session.advanceGuideChord(by: 1)
        XCTAssertEqual(session.currentGuideStepIndex, 0)
        XCTAssertEqual(session.currentGuideChordIndex, 0)

        session.advanceGuideChord(by: 1)
        XCTAssertEqual(session.currentGuideStepIndex, 0)
        XCTAssertEqual(session.currentGuideChordIndex, 1)

        session.advanceGuideChord(by: 1) // past step 0's last chord: skips chord-less step 1
        XCTAssertEqual(session.currentGuideStepIndex, 2)
        XCTAssertEqual(session.currentGuideChordIndex, 0)

        session.advanceGuideChord(by: 1)
        XCTAssertEqual(session.currentGuideStepIndex, 2)
        XCTAssertEqual(session.currentGuideChordIndex, 1)

        session.advanceGuideChord(by: 1) // end of the whole sequence: no-op
        XCTAssertEqual(session.currentGuideStepIndex, 2)
        XCTAssertEqual(session.currentGuideChordIndex, 1)

        session.advanceGuideChord(by: -1)
        session.advanceGuideChord(by: -1) // skips chord-less step 1 backward too
        XCTAssertEqual(session.currentGuideStepIndex, 0)
        XCTAssertEqual(session.currentGuideChordIndex, 1) // step 0's LAST chord, not its first

        session.advanceGuideStep(by: 1)
        XCTAssertNil(session.currentGuideChordIndex, "advanceGuideStep resets currentGuideChordIndex")
    }

    func testAdvanceGuideChordDoesNothingWhenGuideIsNotRunning() throws {
        let session = ImprovSession()
        session.newGuideSequence(title: "Not Running")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"), chordProgression: ChordProgressionTemplate(name: "s", degrees: ["I", "V"]))
        session.advanceGuideChord(by: 1)
        XCTAssertNil(session.currentGuideChordIndex)
    }

    func testBuildSoundTrackDetailReflectsEventsAndTrackIDs() throws {
        let session = ImprovSession()
        XCTAssertFalse(session.buildSoundTrackDetail().loaded)

        try session.startRecording(title: "Detail Test")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()

        let detail = session.buildSoundTrackDetail()
        XCTAssertTrue(detail.loaded)
        XCTAssertEqual(detail.title, "Detail Test")
        XCTAssertEqual(detail.events?.count, 2)
        XCTAssertEqual(detail.trackIDs, ["clavier"])
    }

    // MARK: - Scene roles

    func testNewSceneCreatesEmptyActiveScene() {
        let session = ImprovSession()
        XCTAssertNil(session.currentScene)
        session.newScene(title: "Repetition")
        XCTAssertEqual(session.currentScene?.title, "Repetition")
        XCTAssertEqual(session.currentScene?.roles, [])
    }

    func testAddSceneRoleAppendsAndRemoveSceneRoleRemoves() throws {
        let session = ImprovSession()
        session.newScene(title: "Test")
        let roleID = try session.addSceneRole(name: "Piano 1")
        XCTAssertEqual(session.currentScene?.roles.count, 1)
        XCTAssertEqual(session.currentScene?.roles.first?.name, "Piano 1")

        try session.removeSceneRole(roleID)
        XCTAssertEqual(session.currentScene?.roles.count, 0)
    }

    func testSetSceneRoleVolumeUpdatesRoleAndAppliesToAttachedInstrument() throws {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Test")
        let roleID = try session.addSceneRole(name: "Piano")
        try session.attachInstrument(.computerKeyboard, toRole: roleID)

        try session.setSceneRoleVolume(roleID, volume: 0.5)
        XCTAssertEqual(session.currentScene?.roles.first { $0.id == roleID }?.volume, 0.5)

        // Detached role: the volume is still recorded even without a live instrument attached.
        try session.detachInstrument(fromRole: roleID)
        try session.setSceneRoleVolume(roleID, volume: 0.2)
        XCTAssertEqual(session.currentScene?.roles.first { $0.id == roleID }?.volume, 0.2)
    }

    func testSetSceneRoleVolumeWithoutActiveSceneThrows() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.setSceneRoleVolume(UUID(), volume: 0.5)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noSceneLoaded)
        }
    }

    func testAddSceneRoleWithoutActiveSceneThrows() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.addSceneRole(name: "Piano 1")) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noSceneLoaded)
        }
    }

    func testAttachInstrumentAppliesRoleConfigurationAndAutoDetachesFromPreviousRole() throws {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Test")
        let pianoID = try session.addSceneRole(name: "Piano")
        let bassID = try session.addSceneRole(name: "Basse")
        try session.setSceneRoleListening(pianoID, isListening: true)

        try session.attachInstrument(.computerKeyboard, toRole: pianoID)
        XCTAssertEqual(session.currentScene?.roles.first { $0.id == pianoID }?.attachedTrackID, .computerKeyboard)
        XCTAssertTrue(session.tracks.first { $0.id == .computerKeyboard }?.isListening ?? false)

        // Moving the SAME instrument to a different role must auto-detach it from the first,
        // not throw/reject — the actual regression this choke point exists to prevent.
        try session.attachInstrument(.computerKeyboard, toRole: bassID)
        XCTAssertNil(session.currentScene?.roles.first { $0.id == pianoID }?.attachedTrackID)
        XCTAssertEqual(session.currentScene?.roles.first { $0.id == bassID }?.attachedTrackID, .computerKeyboard)
    }

    func testDetachInstrumentClearsAttachmentWithoutStoppingTrack() throws {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Test")
        let roleID = try session.addSceneRole(name: "Piano")
        try session.setSceneRoleListening(roleID, isListening: true)
        try session.attachInstrument(.computerKeyboard, toRole: roleID)
        XCTAssertTrue(session.tracks.first { $0.id == .computerKeyboard }?.isListening ?? false)

        try session.detachInstrument(fromRole: roleID)
        XCTAssertNil(session.currentScene?.roles.first { $0.id == roleID }?.attachedTrackID)
        // Detaching is bookkeeping only — the instrument itself keeps listening, mirroring
        // `stopTrack`'s own "state survives a stop" convention.
        XCTAssertTrue(session.tracks.first { $0.id == .computerKeyboard }?.isListening ?? false)
    }

    func testAttachInstrumentThrowsForUnknownRoleOrTrack() throws {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Test")
        let roleID = try session.addSceneRole(name: "Piano")

        XCTAssertThrowsError(try session.attachInstrument(.computerKeyboard, toRole: UUID())) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .unknownSceneRole)
        }
        XCTAssertThrowsError(try session.attachInstrument(.midiSource(99), toRole: roleID)) { error in
            guard case .unknownTrack = error as? ImprovSession.SessionError else {
                XCTFail("expected .unknownTrack, got \(error)"); return
            }
        }
    }

    func testFreeSceneRolesAndUnassignedInstruments() throws {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Test")
        let pianoID = try session.addSceneRole(name: "Piano")
        _ = try session.addSceneRole(name: "Basse")
        try session.attachInstrument(.computerKeyboard, toRole: pianoID)

        XCTAssertEqual(session.freeSceneRoles().map(\.name), ["Basse"])
        XCTAssertFalse(session.unassignedInstruments().contains { $0.id == .computerKeyboard })
        XCTAssertTrue(session.unassignedInstruments().contains { $0.id == .microphone })
    }

    func testSceneSaveLoadRoundTripReattachesComputerKeyboardAndReportsFreeRoles() throws {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Repetition")
        let pianoID = try session.addSceneRole(name: "Piano")
        _ = try session.addSceneRole(name: "Basse")
        try session.setSceneRoleListening(pianoID, isListening: true)
        try session.attachInstrument(.computerKeyboard, toRole: pianoID)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveScene(title: "Repetition", toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.start()
        try reloaded.loadScene(fromJSONFile: tempFile.path)

        XCTAssertEqual(reloaded.currentScene?.roles.count, 2)
        let reloadedPiano = reloaded.currentScene?.roles.first { $0.name == "Piano" }
        XCTAssertEqual(reloadedPiano?.attachedTrackID, .computerKeyboard)
        XCTAssertTrue(reloaded.tracks.first { $0.id == .computerKeyboard }?.isListening ?? false)
        let reloadedBasse = reloaded.currentScene?.roles.first { $0.name == "Basse" }
        XCTAssertNil(reloadedBasse?.attachedTrackID)
        // The direct fix for the reported bug: a role that couldn't reattach is reported, not
        // silently dropped.
        XCTAssertTrue(reloaded.log.contains { $0.contains("Basse") && $0.contains("libre") })
    }

    /// Regression test for a real "assigned a sound but heard nothing" bug: `setSceneRoleSound`
    /// used to swallow `setInstrument`'s error (`try?`), committing `role.soundName` to the
    /// UI-visible value regardless of whether the underlying sampler actually loaded anything —
    /// the picker looked like it worked even when it silently hadn't. It must now surface the
    /// failure (a real `throw`) AND leave `role.soundName` untouched, not pointing at a sound
    /// that was never actually loaded.
    func testSetSceneRoleSoundThrowsAndLeavesRoleUnchangedWhenInstrumentLoadFails() throws {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Test")
        let roleID = try session.addSceneRole(name: "Piano")
        try session.attachInstrument(.computerKeyboard, toRole: roleID)

        // No sample folder listed at all yet — `setInstrument` throws `.noSampleFolderListed`
        // before ever touching a sampler, the simplest reliable way to force a failure here
        // without needing a real .sf2/.dls/.aupreset fixture on disk.
        XCTAssertThrowsError(try session.setSceneRoleSound(roleID, soundName: "some-sound.sf2"))
        XCTAssertNil(session.currentScene?.roles.first { $0.id == roleID }?.soundName)
        XCTAssertFalse(session.tracks.first { $0.id == .computerKeyboard }?.soundEnabled ?? true)
    }

    /// Regression test for a real "plays but no sound comes out" bug, reported after using the
    /// Scene tab's normal workflow (attach an instrument to a role, pick its sound): once a real
    /// sound was successfully assigned, re-attaching the SAME instrument to the SAME role (what
    /// happens on a scene reload, or moving an instrument to another role and back) silently
    /// muted it again. Root cause: `SceneRole.soundEnabled` defaulted to `false` and nothing in
    /// `setSceneRoleSound` ever set it `true` even on a successful assignment, so
    /// `applyRoleConfiguration` (re-run on every attach) always saw a "declared disabled" role
    /// and force-disabled the track's sampler right after `setInstrument` had just enabled it.
    /// Uses macOS's own built-in General MIDI DLS bank (always present at this fixed path,
    /// unlike a project-bundled .sf2 which doesn't exist in this repo) as a REAL, loadable
    /// instrument — needed to actually exercise `setInstrument`'s success path, not just its
    /// already-tested failure path above.
    func testSceneRoleSoundStaysEnabledWhenTheSameInstrumentIsReattached() throws {
        let systemDLS = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: systemDLS.path), "macOS system GM soundbank not found on this machine")

        let sampleDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sampleDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sampleDir) }
        let sampleName = "gs_instruments.dls"
        try FileManager.default.copyItem(at: systemDLS, to: sampleDir.appendingPathComponent(sampleName))

        let session = ImprovSession()
        try session.start()
        try session.listSampleFiles(in: sampleDir.path)
        session.newScene(title: "Test")
        let roleID = try session.addSceneRole(name: "Piano")
        try session.attachInstrument(.computerKeyboard, toRole: roleID)

        try session.setSceneRoleSound(roleID, soundName: sampleName)
        XCTAssertTrue(session.tracks.first { $0.id == .computerKeyboard }?.soundEnabled ?? false)
        XCTAssertEqual(session.currentScene?.roles.first { $0.id == roleID }?.soundEnabled, true)

        // The actual regression: re-attaching used to silently re-mute the track here.
        try session.attachInstrument(.computerKeyboard, toRole: roleID)
        XCTAssertTrue(session.tracks.first { $0.id == .computerKeyboard }?.soundEnabled ?? false)
    }

    /// Regression test for a real "plays but no sound comes out" bug, reported live on a LUMI
    /// Keys MIDI track: `tracks[].soundEnabled` was `true`, a sampler existed, `startNote` was
    /// genuinely being called on every keypress — yet nothing played. Root cause: `setInstrument`
    /// reused an EXISTING `SamplerUnit` (e.g. one previously silenced by `setSoundEnabled(false,
    /// ...)`, which calls `SamplerUnit.stop()`) without ever restarting its `AVAudioEngine` —
    /// only the "brand new `SamplerUnit`" branch called `.start()`. A stopped `AVAudioEngine`
    /// makes `AVAudioUnitSampler.startNote`/`stopNote` a silent no-op with no error, confirmed in
    /// isolation. Same real GM DLS bank as the test above, needed to exercise the actual reuse
    /// path in `setInstrument`, not just a mocked one.
    func testSetInstrumentRestartsAPreviouslyStoppedSampler() throws {
        let systemDLS = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: systemDLS.path), "macOS system GM soundbank not found on this machine")

        let sampleDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sampleDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sampleDir) }
        let sampleName = "gs_instruments.dls"
        try FileManager.default.copyItem(at: systemDLS, to: sampleDir.appendingPathComponent(sampleName))

        let session = ImprovSession()
        try session.start()
        try session.listSampleFiles(in: sampleDir.path)

        try session.setInstrument(named: sampleName, for: .computerKeyboard)
        XCTAssertEqual(session.samplerIsRunning(for: .computerKeyboard), true)

        // Silences the track the same way a muted-but-remembered role does — the sampler
        // object itself survives (`samplers[id]` stays non-nil), only its engine stops.
        try session.setSoundEnabled(false, for: .computerKeyboard)
        XCTAssertEqual(session.samplerIsRunning(for: .computerKeyboard), false)

        // The actual regression: re-picking a sound for this track used to reuse that same,
        // still-stopped `SamplerUnit` without restarting it — `soundEnabled` would read `true`
        // again, but every future `startNote` would stay silent forever.
        try session.setInstrument(named: sampleName, for: .computerKeyboard)
        XCTAssertTrue(session.tracks.first { $0.id == .computerKeyboard }?.soundEnabled ?? false)
        XCTAssertEqual(session.samplerIsRunning(for: .computerKeyboard), true)
    }

    func testLoadSceneMigratesLegacyFlatTrackFormat() throws {
        let legacyJSON = """
        {"title": "Ancienne Scene", "tracks": [
            {"trackID": "clavier", "isListening": true, "soundEnabled": true, "instrumentName": "mcb.sf2"}
        ]}
        """
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try legacyJSON.write(to: tempFile, atomically: true, encoding: .utf8)

        let session = ImprovSession()
        try session.start()
        try session.loadScene(fromJSONFile: tempFile.path)

        XCTAssertEqual(session.currentScene?.title, "Ancienne Scene")
        XCTAssertEqual(session.currentScene?.roles.count, 1)
        let role = session.currentScene?.roles.first
        XCTAssertEqual(role?.name, "Clavier ordinateur")
        XCTAssertEqual(role?.attachedTrackID, .computerKeyboard)
        XCTAssertEqual(role?.lastAttachedInstrument, .computerKeyboard)
    }

    /// `SceneRole.soundPreset` was added after `soundName` was already in use on real saved
    /// scenes — a scene file saved before multi-preset support (no `soundPreset` key at all
    /// in its `roles` entries, only `soundName`) must still decode, with `soundPreset == nil`
    /// (that role's sound just uses the file's own default preset, exactly as before).
    func testSceneRoleDecodesPreExistingJSONWithNoSoundPresetKeyAsNilPreset() throws {
        let json = """
        {"title": "Ancienne Scene", "roles": [
            {"id": "\(UUID().uuidString)", "name": "Piano 1", "soundName": "Piano.sf2", "isListening": false, "soundEnabled": true}
        ]}
        """
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try json.write(to: tempFile, atomically: true, encoding: .utf8)

        let session = ImprovSession()
        try session.start()
        try session.loadScene(fromJSONFile: tempFile.path)

        let role = session.currentScene?.roles.first
        XCTAssertEqual(role?.soundName, "Piano.sf2")
        XCTAssertNil(role?.soundPreset)
    }

    func testSetSceneRoleSoundRoundTripsAPresetThroughSaveAndLoad() throws {
        let session = ImprovSession()
        try session.start()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("Bank.sf2"))
        try session.listSampleFiles(in: folder.path)

        session.newScene(title: "Scene")
        let roleID = try session.addSceneRole(name: "Piano")
        let preset = SoundFontPresetIdentity(program: 19, bank: 0)
        // No instrument attached to the role yet, so `setInstrument` isn't reached — this only
        // exercises persistence of the role's own declared sound/preset, same scoping as
        // `testSceneSaveAndLoadRoundTripsTrackListeningAndSound`.
        try session.setSceneRoleSound(roleID, soundName: "Bank.sf2", preset: preset)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveScene(title: "Scene", toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.start()
        try reloaded.loadScene(fromJSONFile: tempFile.path)
        XCTAssertEqual(reloaded.currentScene?.roles.first?.soundPreset, preset)
    }

    func testLoadSceneDoesNotReattachMidiMergedHintInIndividualMode() throws {
        // `.midiMerged` has no CoreMIDI dependency (a singleton, unlike `.midiSource`), so this
        // is the one `matches(_:_:)` case fully testable without real hardware — see
        // `ImprovSession.matches(_:_:)`'s own doc comment for why `.midiPort` matching isn't
        // covered here (it needs a real or injectable CoreMIDI source list this test suite has
        // no way to control).
        let scene = Scene(title: "Old Setup", roles: [
            SceneRole(name: "Synth", lastAttachedInstrument: .midiMerged),
        ])
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try JSONEncoder().encode(scene).write(to: tempFile)

        let session = ImprovSession()
        try session.start()
        session.setMIDIFusionMode(.individual) // no MIDI hardware here, so this yields zero midi tracks
        try session.loadScene(fromJSONFile: tempFile.path)

        XCTAssertNil(session.currentScene?.roles.first?.attachedTrackID)
    }

    // MARK: - Localization

    func testMigrateLanguageSettingDefaultsToFrenchAndPersistsChange() throws {
        let session = makeTestSession()
        try session.start()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json").path

        session.migrateLanguageSettingFromJSONIfNeeded(fromJSONFile: path)
        XCTAssertEqual(session.currentLanguage, .fr)

        try session.setLanguage(.de)
        XCTAssertEqual(session.currentLanguage, .de)

        // Re-migrating (as `setSettingsFolder` would on a relaunch pointed at the same store)
        // must load the persisted value back rather than re-seeding French.
        session.migrateLanguageSettingFromJSONIfNeeded(fromJSONFile: path)
        XCTAssertEqual(session.currentLanguage, .de)
    }

    func testSetLanguageUpdatesCurrentLanguageAndWebConsoleState() throws {
        let session = makeTestSession()
        try session.start()
        try session.setLanguage(.de)
        XCTAssertEqual(session.currentLanguage, .de)
        XCTAssertEqual(session.buildWebConsoleState().language, "de")
    }

    // MARK: - LLM API keys (Keychain-backed)

    /// Real Keychain, unique env var per test + cleanup via `defer` — same convention as
    /// `APIKeyStoreTests` (`Tests/LLMEngineTests`), since there's no mock/injection point.
    func testMigrateLLMAPIKeysFromJSONMovesKeysIntoKeychainAndDeletesThePlaintextFile() throws {
        let envVar = "ImprovSessionTests_MigrateLLMAPIKeys_\(UUID().uuidString)"
        defer { APIKeyStore.persist(nil, forEnvVar: envVar) }

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try JSONEncoder().encode(LLMAPIKeysFile(keysByEnvVar: [envVar: "sk-test-123"])).write(to: tempFile)

        let session = makeTestSession()
        session.migrateLLMAPIKeysFromJSONIfNeeded(fromJSONFile: tempFile.path)

        XCTAssertEqual(session.llmAPIKeyEnvVars, [envVar])
        XCTAssertEqual(session.llmAPIKey(forEnvVar: envVar), "sk-test-123")
        XCTAssertEqual(APIKeyStore.resolve(envVar), "sk-test-123")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path), "the plaintext file must be deleted once its keys are in the Keychain")
    }

    func testSetLLMAPIKeyPersistsAndClearingRemovesIt() throws {
        let envVar = "ImprovSessionTests_SetLLMAPIKey_\(UUID().uuidString)"
        defer { APIKeyStore.persist(nil, forEnvVar: envVar) }

        let session = makeTestSession()
        try session.setLLMAPIKey("sk-test-456", forEnvVar: envVar)
        XCTAssertEqual(session.llmAPIKeyEnvVars, [envVar])
        XCTAssertEqual(session.llmAPIKey(forEnvVar: envVar), "sk-test-456")

        try session.setLLMAPIKey("", forEnvVar: envVar)
        XCTAssertFalse(session.llmAPIKeyEnvVars.contains(envVar))
        XCTAssertNil(session.llmAPIKey(forEnvVar: envVar))
    }

    // MARK: - releaseAllKeys

    func testReleaseAllKeysClearsHeldPitchesForOneTrackOnly() throws {
        let session = ImprovSession()
        session.setMIDIFusionMode(.merged) // default is now .individual; this test needs .midiMerged specifically
        try session.startTrack(.computerKeyboard)
        try session.startTrack(.midiMerged)
        session.pressKey(pitch: 60, track: .computerKeyboard)
        session.pressKey(pitch: 64, track: .midiMerged)
        session.pressKey(pitch: 67, track: .midiMerged)
        session.releaseAllKeys(track: .midiMerged)
        XCTAssertEqual(session.tracks.first { $0.id == .midiMerged }?.heldPitches, [])
        XCTAssertEqual(session.tracks.first { $0.id == .computerKeyboard }?.heldPitches, Set([60]))
    }

    // MARK: - Guide sequence

    func testNewGuideSequenceThenAddStepsThenStartAndAdvance() throws {
        let session = ImprovSession()
        XCTAssertNil(session.currentGuide)
        session.newGuideSequence(title: "Practice")
        XCTAssertEqual(session.currentGuide?.title, "Practice")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.addGuideStep(ModeReference(tonic: 2, scaleID: "dorian"))
        XCTAssertEqual(session.currentGuide?.steps.count, 2)

        XCTAssertNil(session.currentGuideStepIndex)
        XCTAssertNil(session.currentGuideStepMode())

        try session.startGuide()
        XCTAssertEqual(session.currentGuideStepIndex, 0)
        XCTAssertEqual(session.currentGuideStepMode()?.displayName, "C Major")

        session.advanceGuideStep(by: 1)
        XCTAssertEqual(session.currentGuideStepIndex, 1)
        XCTAssertEqual(session.currentGuideStepMode()?.displayName, "D Dorian")

        session.advanceGuideStep(by: 1)
        XCTAssertEqual(session.currentGuideStepIndex, 1, "advanceGuideStep clamps at the last step")

        session.advanceGuideStep(by: -5)
        XCTAssertEqual(session.currentGuideStepIndex, 0, "advanceGuideStep clamps at the first step")

        session.stopGuide()
        XCTAssertNil(session.currentGuideStepIndex)
    }

    func testSetGuideStepChordQualityChangesOnlyThatChordKeepingItsRoot() throws {
        let session = ImprovSession()
        session.newGuideSequence(title: "Practice")
        let progression = ChordProgressionTemplate(name: "I-IV-V", degrees: ["I", "IV", "V"])
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"), chordProgression: progression)

        try session.setGuideStepChordQuality(stepIndex: 0, chordIndex: 1, templateID: "7")
        let updated = try XCTUnwrap(session.currentGuide?.steps[0].chordProgression)
        XCTAssertEqual(updated[0].chordTemplateID, "Ma", "untouched chords keep their original quality")
        XCTAssertEqual(updated[1].chordTemplateID, "7")
        XCTAssertEqual(updated[1].root, 5, "changing quality never touches the chord's own root")
        XCTAssertEqual(updated[2].chordTemplateID, "Ma")
    }

    func testSetGuideStepChordQualityWithInvalidChordIndexThrows() throws {
        let session = ImprovSession()
        session.newGuideSequence(title: "Practice")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        XCTAssertThrowsError(try session.setGuideStepChordQuality(stepIndex: 0, chordIndex: 0, templateID: "7")) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .invalidChordIndex, "no chord progression at all on this step")
        }
    }

    func testMoveGuideStepsReordersAndKeepsActiveStepPointedAtTheSameStep() throws {
        let session = ImprovSession()
        session.newGuideSequence(title: "Practice")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.addGuideStep(ModeReference(tonic: 2, scaleID: "dorian"))
        try session.addGuideStep(ModeReference(tonic: 7, scaleID: "mixolydian"))
        try session.startGuide(atStepIndex: 1) // the Dorian step

        try session.moveGuideSteps(fromOffsets: [0], toOffset: 3) // Ionian moves to the end
        XCTAssertEqual(session.currentGuide?.steps.map { $0.mode.scaleID }, ["dorian", "mixolydian", "ionian"])
        XCTAssertEqual(session.currentGuideStepIndex, 0, "the active step follows Dorian to its new position")
        XCTAssertEqual(session.currentGuideStepMode()?.displayName, "D Dorian")
    }

    func testMoveGuideStepChordsReordersWithinOneStepOnly() throws {
        let session = ImprovSession()
        session.newGuideSequence(title: "Practice")
        let progression = ChordProgressionTemplate(name: "I-IV-V", degrees: ["I", "IV", "V"])
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"), chordProgression: progression)
        try session.addGuideStep(ModeReference(tonic: 2, scaleID: "dorian"), chordProgression: progression)

        try session.moveGuideStepChords(atStepIndex: 0, fromOffsets: [0], toOffset: 3)
        let reordered = try XCTUnwrap(session.currentGuide?.steps[0].chordProgression)
        XCTAssertEqual(reordered.map(\.root), [5, 7, 0], "IV, V, I after moving I to the end")

        // Step 1 is in D dorian, not C ionian — its own I/IV/V resolve to D(2)/G(7)/A(9), a
        // different absolute root set than step 0's, by design (`resolveChordProgression`
        // resolves each step's template against ITS OWN mode).
        let untouched = try XCTUnwrap(session.currentGuide?.steps[1].chordProgression)
        XCTAssertEqual(untouched.map(\.root), [2, 7, 9], "the sibling step's own progression is unaffected")
    }

    func testSetGuideStepChordProgressionAppliesToAnAlreadyCreatedStepAndCanClearIt() throws {
        let session = ImprovSession()
        session.newGuideSequence(title: "Practice")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian")) // no progression yet

        let progression = ChordProgressionTemplate(name: "ii-V-I", degrees: ["ii", "V", "I"])
        try session.setGuideStepChordProgression(atIndex: 0, template: progression)
        XCTAssertEqual(session.currentGuide?.steps[0].chordProgressionName, "ii-V-I")
        XCTAssertEqual(session.currentGuide?.steps[0].chordProgression?.count, 3)

        try session.setGuideStepChordProgression(atIndex: 0, template: nil)
        XCTAssertNil(session.currentGuide?.steps[0].chordProgressionName)
        XCTAssertNil(session.currentGuide?.steps[0].chordProgression)
    }

    func testAddGuideStepWithoutASequenceThrows() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian")))
    }

    func testAddGuideStepWithUnknownScaleIDThrowsAndDoesNotAppendAStep() {
        let session = ImprovSession()
        session.newGuideSequence(title: "Practice")
        XCTAssertThrowsError(try session.addGuideStep(ModeReference(tonic: 0, scaleID: "majeur"))) // not a real ScaleLibrary id
        XCTAssertEqual(session.currentGuide?.steps.count, 0, "an unresolvable reference doesn't leave a dangling step")
    }

    func testGuideSequenceSaveAndLoadRoundTrips() throws {
        let session = ImprovSession()
        session.newGuideSequence(title: "Round Trip")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.addGuideStep(ModeReference(tonic: 7, scaleID: "mixolydian"))

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveGuideSequence(toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.loadGuideSequence(fromJSONFile: tempFile.path)
        XCTAssertEqual(reloaded.currentGuide, session.currentGuide)
        XCTAssertNil(reloaded.currentGuideStepIndex, "loading a guide sequence resets the current step index")
    }

    func testGuideStepWithChordProgressionRoundTripsThroughJSON() throws {
        let session = ImprovSession()
        session.newGuideSequence(title: "With Progression")
        let blues = ChordProgressionTemplate.builtInDefaults[0] // "Blues 12 mesures"
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"), chordProgression: blues)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveGuideSequence(toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.loadGuideSequence(fromJSONFile: tempFile.path)
        XCTAssertEqual(reloaded.currentGuide?.steps.first?.chordProgressionName, "Blues 12 mesures")
        XCTAssertEqual(reloaded.currentGuide?.steps.first?.chordProgression?.count, 12)
    }

    // MARK: - Guide sequences: store-based CRUD (see GuideSequenceRecord)

    func testMigrateGuideSequencesFindsJSONFilesAndInsertsThem() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sequence = GuideSequence(title: "Practice", steps: [GuideStep(mode: ModeReference(tonic: 0, scaleID: "ionian"))])
        try JSONEncoder().encode(sequence).write(to: folder.appendingPathComponent("practice.json"))

        let session = makeTestSession()
        session.migrateGuideSequencesFromJSONIfNeeded(in: folder.path)
        XCTAssertEqual(session.guideSequenceNames, ["Practice"])
    }

    func testMigrateGuideSequencesIsIdempotent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sequence = GuideSequence(title: "Practice")
        try JSONEncoder().encode(sequence).write(to: folder.appendingPathComponent("practice.json"))

        let session = makeTestSession()
        session.migrateGuideSequencesFromJSONIfNeeded(in: folder.path)
        session.migrateGuideSequencesFromJSONIfNeeded(in: folder.path)
        XCTAssertEqual(session.guideSequenceNames, ["Practice"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("practice.json").path), "the original file must survive migration")
    }

    func testUseGuideSequenceByIndexAndNameLoadFromTheStore() throws {
        let session = makeTestSession()
        session.newGuideSequence(title: "Practice")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.saveGuideSequence(as: "Practice")
        session.newGuideSequence(title: "Other") // clears currentGuide/currentGuideRecordID first

        try session.useGuideSequence(atIndex: 0)
        XCTAssertEqual(session.currentGuide?.title, "Practice")
        XCTAssertEqual(session.currentGuide?.steps.count, 1)

        session.newGuideSequence(title: "Other")
        try session.useGuideSequence(named: "Practice")
        XCTAssertEqual(session.currentGuide?.title, "Practice")
    }

    func testSaveGuideSequenceAsCreatesThenOverwritesOnSameTitle() throws {
        let session = makeTestSession()
        session.newGuideSequence(title: "Draft")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.saveGuideSequence(as: "Final")
        XCTAssertEqual(session.guideSequenceNames, ["Final"])
        XCTAssertEqual(session.currentGuide?.title, "Final", "saveGuideSequence(as:) adopts the new name as the guide's own title")

        try session.addGuideStep(ModeReference(tonic: 7, scaleID: "mixolydian"))
        try session.saveGuideSequence(as: "Final")
        XCTAssertEqual(session.guideSequenceNames, ["Final"], "saving under an existing title overwrites it rather than duplicating")
        try session.useGuideSequence(named: "Final")
        XCTAssertEqual(session.currentGuide?.steps.count, 2, "the overwrite captured the second step")
    }

    func testSaveGuideSequenceBareReSavesToTheSameRecord() throws {
        let session = makeTestSession()
        session.newGuideSequence(title: "Practice")
        try session.saveGuideSequence(as: "Practice")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.saveGuideSequence()

        try session.useGuideSequence(named: "Practice")
        XCTAssertEqual(session.currentGuide?.steps.count, 1)
        XCTAssertEqual(session.guideSequenceNames, ["Practice"], "bare save() must not create a second record")
    }

    func testSaveGuideSequenceBareWithoutHavingSavedOnceThrows() throws {
        let session = makeTestSession()
        session.newGuideSequence(title: "Practice")
        XCTAssertThrowsError(try session.saveGuideSequence()) { error in
            guard case ImprovSession.SessionError.noCurrentGuideFile = error else {
                return XCTFail("expected noCurrentGuideFile, got \(error)")
            }
        }
    }

    func testDeleteGuideSequenceRemovesItFromTheStore() throws {
        let session = makeTestSession()
        session.newGuideSequence(title: "Practice")
        try session.saveGuideSequence(as: "Practice")
        XCTAssertEqual(session.guideSequenceNames, ["Practice"])

        try session.deleteGuideSequence(atIndex: 0)
        XCTAssertEqual(session.guideSequenceNames, [])
    }

    func testRenameCurrentGuideOnAnAnonymousGuideInsertsItsFirstRecord() throws {
        let session = makeTestSession()
        session.newGuideSequence(title: "")
        XCTAssertNil(session.currentGuideRecordID)

        try session.renameCurrentGuide(to: "First Save")
        XCTAssertEqual(session.currentGuide?.title, "First Save")
        XCTAssertNotNil(session.currentGuideRecordID)
        XCTAssertEqual(session.guideSequenceNames, ["First Save"])
    }

    func testRenameCurrentGuideOnAnAlreadyNamedGuideUpdatesTheSameRecordInPlace() throws {
        let session = makeTestSession()
        session.newGuideSequence(title: "Practice")
        try session.saveGuideSequence(as: "Practice")
        let recordID = session.currentGuideRecordID

        try session.renameCurrentGuide(to: "Renamed")
        XCTAssertEqual(session.currentGuideRecordID, recordID, "same record identity, not a fresh insert")
        XCTAssertEqual(session.guideSequenceNames, ["Renamed"])
    }

    func testRenameGuideSequenceAtIndexUpdatesTheListAndSyncsTheActiveGuideWhenItMatches() throws {
        let session = makeTestSession()
        session.newGuideSequence(title: "Practice")
        try session.saveGuideSequence(as: "Practice")

        try session.renameGuideSequence(atIndex: 0, name: "Warmup")
        XCTAssertEqual(session.guideSequenceNames, ["Warmup"])
        XCTAssertEqual(session.currentGuide?.title, "Warmup", "renaming the active guide's own record keeps currentGuide in sync")
    }

    func testRenameGuideSequenceAtIndexOnANonActiveGuideLeavesCurrentGuideUntouched() throws {
        let session = makeTestSession()
        session.newGuideSequence(title: "Practice")
        try session.saveGuideSequence(as: "Practice")
        session.newGuideSequence(title: "Other")
        try session.saveGuideSequence(as: "Other")
        // currentGuide is "Other"; guideSequenceNames is sorted alphabetically, so "Practice" is index 1.
        XCTAssertEqual(session.guideSequenceNames, ["Other", "Practice"])
        try session.renameGuideSequence(atIndex: 1, name: "Warmup")
        XCTAssertEqual(session.currentGuide?.title, "Other")
        XCTAssertEqual(Set(session.guideSequenceNames), Set(["Warmup", "Other"]))
    }

    func testExportedGuideDataReturnsTheStoredGuideAsDecodableJSON() throws {
        let session = makeTestSession()
        session.newGuideSequence(title: "Practice")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.saveGuideSequence(as: "Practice")

        let data = try session.exportedGuideData(atIndex: 0)
        let decoded = try JSONDecoder().decode(GuideSequence.self, from: data)
        XCTAssertEqual(decoded.title, "Practice")
        XCTAssertEqual(decoded.steps.count, 1)
    }

    func testCreateNewGuideSequencePersistsANamedGuideBeforeStartingAFreshAnonymousOne() throws {
        let session = makeTestSession()
        session.newGuideSequence(title: "Practice")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.saveGuideSequence(as: "Practice")

        try session.addGuideStep(ModeReference(tonic: 7, scaleID: "mixolydian"))
        try session.createNewGuideSequence()

        XCTAssertEqual(session.currentGuide?.title, "")
        XCTAssertNil(session.currentGuideRecordID)
        try session.useGuideSequence(named: "Practice")
        XCTAssertEqual(session.currentGuide?.steps.count, 2, "the second step was saved before switching away")
    }

    func testCreateNewGuideSequenceDiscardsAnAnonymousGuideWithoutSavingIt() throws {
        let session = makeTestSession()
        session.newGuideSequence(title: "")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))

        try session.createNewGuideSequence()
        XCTAssertEqual(session.guideSequenceNames, [], "an anonymous guide is never persisted just by moving on")
    }

    func testEnsureGuideReadyForLaunchStartsAnonymousGuideWhenNoneAreSaved() {
        let session = makeTestSession()
        session.ensureGuideReadyForLaunch()
        XCTAssertEqual(session.currentGuide?.title, "")
        XCTAssertNil(session.currentGuideRecordID)
    }

    func testEnsureGuideReadyForLaunchLeavesNoActiveGuideWhenOneIsSaved() throws {
        let schema = Schema([GuideSequenceRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))

        let session = ImprovSession(modelContainer: container)
        session.newGuideSequence(title: "Practice")
        try session.saveGuideSequence(as: "Practice")

        // A fresh session sharing the same store — nothing active yet, one guide already saved.
        // Mirrors real launch order: `migrateGuideSequencesFromJSONIfNeeded` refreshes
        // `guideSequenceNames` from the shared store before `ensureGuideReadyForLaunch` reads it.
        let fresh = ImprovSession(modelContainer: container)
        let emptyFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyFolder) }
        fresh.migrateGuideSequencesFromJSONIfNeeded(in: emptyFolder.path)
        fresh.ensureGuideReadyForLaunch()
        XCTAssertNil(fresh.currentGuide, "even a single saved guide requires an explicit pick — the list screen should show")
    }

    /// Every guide file saved before chord progressions existed stores each step as a bare
    /// `ModeReference` (no "mode" key) — `GuideStep.init(from:)` must still load these.
    func testGuideStepDecodesOldBareModeReferenceFormat() throws {
        let json = #"{"title":"Old Format","steps":[{"scaleID":"dorian","tonic":2}]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(GuideSequence.self, from: json)
        XCTAssertEqual(decoded.steps.count, 1)
        XCTAssertEqual(decoded.steps.first?.mode, ModeReference(tonic: 2, scaleID: "dorian"))
        XCTAssertNil(decoded.steps.first?.chordProgressionName)
        XCTAssertNil(decoded.steps.first?.chordProgression)
    }

    // MARK: - Roman numeral / chord progression resolution

    func testRomanNumeralChordParseHandlesUpperLowerAndDiminished() {
        XCTAssertEqual(RomanNumeralChord.parse("I")?.quality, .major)
        XCTAssertEqual(RomanNumeralChord.parse("I")?.degree, 1)
        XCTAssertEqual(RomanNumeralChord.parse("vi")?.quality, .minor)
        XCTAssertEqual(RomanNumeralChord.parse("vi")?.degree, 6)
        XCTAssertEqual(RomanNumeralChord.parse("vii°")?.quality, .diminished)
        XCTAssertEqual(RomanNumeralChord.parse("vii°")?.degree, 7)
        XCTAssertNil(RomanNumeralChord.parse("VIII"), "VIII is not a valid roman numeral (out of range)")
        XCTAssertNil(RomanNumeralChord.parse("xyz"))
    }

    func testResolveChordProgressionAppliesLiteralCaseAsQualityInCIonian() {
        let session = ImprovSession()
        let mode = Mode(tonic: PitchClass(0), scale: ScaleLibrary.byID("ionian")!)
        let blues = ChordProgressionTemplate.builtInDefaults[0] // I I I I IV IV I I V IV I I
        let resolved = session.resolveChordProgression(blues, in: mode)
        XCTAssertEqual(resolved.count, 12)
        XCTAssertEqual(resolved.first?.root, 0)
        XCTAssertEqual(resolved.first?.chordTemplateID, "Ma", "I is taken literally as major")
        XCTAssertEqual(resolved[4].root, 5, "5th chord (IV) is rooted on F")
        XCTAssertEqual(resolved[8].root, 7, "9th chord (V) is rooted on G")
    }

    // MARK: - TrackID

    func testTrackIDWireIDTextRoundTrips() throws {
        for id: TrackID in [.midiMerged, .computerKeyboard, .webKeyboard(clientID: "abc-123"), .microphone, .midiSource(0), .midiSource(3)] {
            let wireText = try XCTUnwrap(id.wireIDText, "\(id) has no wireIDText")
            XCTAssertEqual(TrackID(wireIDText: wireText), id)
        }
        XCTAssertNil(TrackID(wireIDText: "not-a-real-id"))
    }

    func testTrackRecordsMostRecentMIDIChannel() throws {
        let session = ImprovSession()
        session.setMIDIFusionMode(.merged)
        try session.startTrack(.midiMerged)
        XCTAssertNil(session.tracks.first { $0.id == .midiMerged }?.lastChannel)
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 3), track: .midiMerged)
        XCTAssertEqual(session.tracks.first { $0.id == .midiMerged }?.lastChannel, 3)
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 62, velocity: 100, channel: 7), track: .midiMerged)
        XCTAssertEqual(session.tracks.first { $0.id == .midiMerged }?.lastChannel, 7)
    }

    /// Regression test for a real reported bug: `displayedChannel(for:)` showed "canal 1" for
    /// the computer keyboard after typing a single note. Root cause: `lastChannel` is set by
    /// `updateRecognitionState` for ANY track, not just MIDI ones — `pressKey` defaults
    /// `channel` to 0 — and `displayedChannel` used to return it unconditionally. The computer
    /// keyboard isn't a MIDI device at all, so it should never report a channel.
    func testDisplayedChannelIsNilForComputerKeyboardEvenAfterPlaying() throws {
        let session = ImprovSession()
        try session.start()
        try session.startTrack(.computerKeyboard)
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)

        let track = try XCTUnwrap(session.tracks.first { $0.id == .computerKeyboard })
        XCTAssertNotNil(track.lastChannel, "sanity check: lastChannel really is set by playing")
        XCTAssertNil(session.displayedChannel(for: track))
    }

    // MARK: - Scene (basic, non-role-based)

    func testSceneSaveAndLoadRoundTripsTrackListeningAndSound() throws {
        let session = ImprovSession()
        try session.start()
        try session.startTrack(.computerKeyboard)
        try session.setSoundEnabled(true, for: .computerKeyboard)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveScene(title: "Test Scene", toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.start()
        let before = reloaded.tracks.first { $0.id == .computerKeyboard }
        XCTAssertEqual(before?.isListening, false)

        try reloaded.loadScene(fromJSONFile: tempFile.path)
        let after = reloaded.tracks.first { $0.id == .computerKeyboard }
        XCTAssertEqual(after?.isListening, true)
        XCTAssertEqual(after?.soundEnabled, true)
    }

    /// Real bug fixed 2026-07-27: loading a scene used to leave any track NOT mentioned by a
    /// role exactly as it already was (e.g. still listening from this app's own "start every
    /// MIDI track at launch" convenience) — so Studio could show an instrument actively
    /// listening/sounding that the loaded scene's own role list said nothing about, or even
    /// explicitly declared muted. The scene is now authoritative: anything it doesn't attach
    /// gets stopped, so what's actually happening always matches what the scene declares.
    func testLoadSceneStopsTracksNotMentionedByAnyRole() throws {
        let session = ImprovSession()
        try session.start()
        let emptyScene = Scene(title: "Empty", roles: [])
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try JSONEncoder().encode(emptyScene).write(to: tempFile)

        try session.startTrack(.computerKeyboard)
        try session.loadScene(fromJSONFile: tempFile.path)
        XCTAssertEqual(session.tracks.first { $0.id == .computerKeyboard }?.isListening, false)
    }

    /// The flip side of the above: a role explicitly attached AND declared listening must
    /// still end up actually listening (the scene being authoritative cuts both ways).
    func testLoadSceneStartsAttachedRoleDeclaredListening() throws {
        let session = ImprovSession()
        try session.start()
        var scene = Scene(title: "Test", roles: [
            SceneRole(name: "Clavier", isListening: true, attachedTrackID: .computerKeyboard),
        ])
        scene.roles[0].lastAttachedInstrument = .computerKeyboard
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try JSONEncoder().encode(scene).write(to: tempFile)

        try session.loadScene(fromJSONFile: tempFile.path)
        XCTAssertEqual(session.tracks.first { $0.id == .computerKeyboard }?.isListening, true)
    }

    /// A role attached but declared MUTED (`isListening: false`) must stop a track that was
    /// already listening beforehand — the exact bug reported: a scene's role shown muted in
    /// the UI, but the same instrument kept listening/recognizing chords in Studio regardless.
    func testLoadSceneStopsAttachedRoleDeclaredMuted() throws {
        let session = ImprovSession()
        try session.start()
        var scene = Scene(title: "Test", roles: [
            SceneRole(name: "Clavier", isListening: false, attachedTrackID: .computerKeyboard),
        ])
        scene.roles[0].lastAttachedInstrument = .computerKeyboard
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try JSONEncoder().encode(scene).write(to: tempFile)

        try session.startTrack(.computerKeyboard) // already listening BEFORE the scene loads
        try session.loadScene(fromJSONFile: tempFile.path)
        XCTAssertEqual(session.tracks.first { $0.id == .computerKeyboard }?.isListening, false)
    }

    // MARK: - Scenes: store-based CRUD (see SceneRecord)

    func testMigrateScenesFindsJSONFilesAndInsertsThem() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = Scene(title: "Practice", roles: [SceneRole(name: "Piano")])
        try JSONEncoder().encode(scene).write(to: folder.appendingPathComponent("practice.json"))

        let session = makeTestSession()
        session.migrateScenesFromJSONIfNeeded(in: folder.path)
        XCTAssertEqual(session.sceneNames, ["Practice"])
    }

    func testMigrateScenesIsIdempotent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let scene = Scene(title: "Practice")
        try JSONEncoder().encode(scene).write(to: folder.appendingPathComponent("practice.json"))

        let session = makeTestSession()
        session.migrateScenesFromJSONIfNeeded(in: folder.path)
        session.migrateScenesFromJSONIfNeeded(in: folder.path)
        XCTAssertEqual(session.sceneNames, ["Practice"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("practice.json").path), "the original file must survive migration")
    }

    func testSaveSceneAsCreatesThenOverwritesOnSameTitle() throws {
        let session = makeTestSession()
        try session.start()
        session.newScene(title: "Draft")
        try session.addSceneRole(name: "Piano")
        try session.saveScene(title: "Final", as: "Final")
        XCTAssertEqual(session.sceneNames, ["Final"])
        XCTAssertEqual(session.currentScene?.title, "Final")

        try session.addSceneRole(name: "Basse")
        try session.saveScene(title: "Final", as: "Final")
        XCTAssertEqual(session.sceneNames, ["Final"], "saving under an existing title overwrites it rather than duplicating")
        try session.useScene(named: "Final")
        XCTAssertEqual(session.currentScene?.roles.count, 2, "the overwrite captured the second role")
    }

    func testUseSceneByIndexAndNameLoadFromTheStore() throws {
        let session = makeTestSession()
        try session.start()
        session.newScene(title: "Practice")
        try session.addSceneRole(name: "Piano")
        try session.saveScene(title: "Practice", as: "Practice")
        session.newScene(title: "Other")

        try session.useScene(atIndex: 0)
        XCTAssertEqual(session.currentScene?.title, "Practice")
        XCTAssertEqual(session.currentScene?.roles.count, 1)

        session.newScene(title: "Other")
        try session.useScene(named: "Practice")
        XCTAssertEqual(session.currentScene?.title, "Practice")
    }

    func testDeleteSceneRemovesItFromTheStore() throws {
        let session = makeTestSession()
        try session.start()
        session.newScene(title: "Practice")
        try session.saveScene(title: "Practice", as: "Practice")
        XCTAssertEqual(session.sceneNames, ["Practice"])

        try session.deleteScene(atIndex: 0)
        XCTAssertEqual(session.sceneNames, [])
    }

    func testSaveSceneBareThrowsWithoutAnActiveOrNamedScene() {
        let session = makeTestSession()
        XCTAssertThrowsError(try session.saveScene())
        session.newScene(title: "Draft")
        XCTAssertThrowsError(try session.saveScene(), "still anonymous — never saved under a name")
    }

    func testSaveSceneBareUpdatesTheSameRecordEvenAfterATitleChange() throws {
        let session = makeTestSession()
        try session.start()
        session.newScene(title: "Practice")
        try session.saveScene(title: "Practice", as: "Practice")

        try session.addSceneRole(name: "Piano")
        try session.renameCurrentScene(to: "Practice")
        try session.addSceneRole(name: "Basse")
        try session.saveScene()

        XCTAssertEqual(session.sceneNames, ["Practice"], "no duplicate record was created")
        try session.useScene(named: "Practice")
        XCTAssertEqual(session.currentScene?.roles.count, 2)
    }

    func testRenameCurrentSceneOnAnAnonymousSceneInsertsItsFirstRecord() throws {
        let session = makeTestSession()
        try session.start()
        session.newScene(title: "")
        XCTAssertNil(session.currentSceneRecordID)

        try session.renameCurrentScene(to: "First Save")
        XCTAssertEqual(session.currentScene?.title, "First Save")
        XCTAssertNotNil(session.currentSceneRecordID)
        XCTAssertEqual(session.sceneNames, ["First Save"])
    }

    func testRenameCurrentSceneOnAnAlreadyNamedSceneUpdatesTheSameRecordInPlace() throws {
        let session = makeTestSession()
        try session.start()
        session.newScene(title: "Practice")
        try session.saveScene(title: "Practice", as: "Practice")
        let recordID = session.currentSceneRecordID

        try session.renameCurrentScene(to: "Renamed")
        XCTAssertEqual(session.currentSceneRecordID, recordID, "same record identity, not a fresh insert")
        XCTAssertEqual(session.sceneNames, ["Renamed"])
    }

    func testRenameSceneAtIndexUpdatesTheListAndSyncsTheActiveSceneWhenItMatches() throws {
        let session = makeTestSession()
        try session.start()
        session.newScene(title: "Practice")
        try session.saveScene(title: "Practice", as: "Practice")

        try session.renameScene(atIndex: 0, name: "Warmup")
        XCTAssertEqual(session.sceneNames, ["Warmup"])
        XCTAssertEqual(session.currentScene?.title, "Warmup", "renaming the active scene's own record keeps currentScene in sync")
    }

    func testRenameSceneAtIndexOnANonActiveSceneLeavesCurrentSceneUntouched() throws {
        let session = makeTestSession()
        try session.start()
        session.newScene(title: "Practice")
        try session.saveScene(title: "Practice", as: "Practice")
        session.newScene(title: "Other")
        try session.saveScene(title: "Other", as: "Other")
        // currentScene is "Other"; sceneNames is sorted alphabetically, so "Practice" is index 1.
        XCTAssertEqual(session.sceneNames, ["Other", "Practice"])
        try session.renameScene(atIndex: 1, name: "Warmup")
        XCTAssertEqual(session.currentScene?.title, "Other")
        XCTAssertEqual(Set(session.sceneNames), Set(["Warmup", "Other"]))
    }

    func testExportedSceneDataReturnsTheStoredSceneAsDecodableJSON() throws {
        let session = makeTestSession()
        try session.start()
        session.newScene(title: "Practice")
        try session.addSceneRole(name: "Piano")
        try session.saveScene(title: "Practice", as: "Practice")

        let data = try session.exportedSceneData(atIndex: 0)
        let decoded = try JSONDecoder().decode(Scene.self, from: data)
        XCTAssertEqual(decoded.title, "Practice")
        XCTAssertEqual(decoded.roles.count, 1)
    }

    func testCreateNewScenePersistsANamedSceneBeforeStartingAFreshAnonymousOne() throws {
        let session = makeTestSession()
        try session.start()
        session.newScene(title: "Practice")
        try session.addSceneRole(name: "Piano")
        try session.saveScene(title: "Practice", as: "Practice")

        try session.addSceneRole(name: "Basse")
        try session.createNewScene()

        XCTAssertEqual(session.currentScene?.title, "")
        XCTAssertNil(session.currentSceneRecordID)
        try session.useScene(named: "Practice")
        XCTAssertEqual(session.currentScene?.roles.count, 2, "the second role was saved before switching away")
    }

    func testCreateNewSceneDiscardsAnAnonymousSceneWithoutSavingIt() throws {
        let session = makeTestSession()
        try session.start()
        session.newScene(title: "")
        try session.addSceneRole(name: "Piano")

        try session.createNewScene()
        XCTAssertEqual(session.sceneNames, [], "an anonymous scene is never persisted just by moving on")
    }

    func testEnsureSceneReadyForLaunchStartsAnonymousSceneWhenNoneAreSaved() throws {
        let session = makeTestSession()
        try session.start()
        session.ensureSceneReadyForLaunch()
        XCTAssertEqual(session.currentScene?.title, "")
        XCTAssertNil(session.currentSceneRecordID)
    }

    func testEnsureSceneReadyForLaunchLeavesNoActiveSceneWhenOneIsSaved() throws {
        let schema = Schema([SceneRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))

        let session = ImprovSession(modelContainer: container)
        try session.start()
        session.newScene(title: "Practice")
        try session.saveScene(title: "Practice", as: "Practice")

        // A fresh session sharing the same store — nothing active yet, one scene already saved.
        // Mirrors real launch order (`configureDefaultFolders`): `migrateScenesFromJSONIfNeeded`
        // refreshes `sceneNames` from the shared store before `ensureSceneReadyForLaunch` reads it.
        let fresh = ImprovSession(modelContainer: container)
        try fresh.start()
        let emptyFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyFolder) }
        fresh.migrateScenesFromJSONIfNeeded(in: emptyFolder.path)
        fresh.ensureSceneReadyForLaunch()
        XCTAssertNil(fresh.currentScene, "even a single saved scene requires an explicit pick — the list screen should show")
    }

    func testEnsureSceneReadyForLaunchLeavesNoActiveSceneWhenSeveralAreSaved() throws {
        let schema = Schema([SceneRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))

        let session = ImprovSession(modelContainer: container)
        try session.start()
        session.newScene(title: "Practice")
        try session.saveScene(title: "Practice", as: "Practice")
        session.newScene(title: "Other")
        try session.saveScene(title: "Other", as: "Other")

        let fresh = ImprovSession(modelContainer: container)
        try fresh.start()
        let emptyFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyFolder) }
        fresh.migrateScenesFromJSONIfNeeded(in: emptyFolder.path)
        fresh.ensureSceneReadyForLaunch()
        XCTAssertNil(fresh.currentScene, "several scenes saved — the pick-or-create screen should decide, not an auto-load")
    }

    // MARK: - Color palettes

    func testColorPaletteFileRoundTrips() throws {
        let file = ColorPaletteFile(palettes: ColorPalette.builtInDefaults)
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(ColorPaletteFile.self, from: data)
        XCTAssertEqual(decoded.palettes, ColorPalette.builtInDefaults)
    }

    func testBuiltInDefaultPalettesAreThreeDistinctFullPalettes() {
        XCTAssertEqual(ColorPalette.builtInDefaults.count, 3)
        XCTAssertEqual(Set(ColorPalette.builtInDefaults.map(\.name)).count, 3)
        for palette in ColorPalette.builtInDefaults {
            XCTAssertEqual(palette.colors.count, 12, "\(palette.name) has 12 colors")
            XCTAssertEqual(Set(palette.colors).count, 12, "\(palette.name)'s 12 colors are distinct")
            XCTAssertEqual(palette.textColors.count, 12, "\(palette.name) has 12 text colors")
            for textColor in palette.textColors {
                XCTAssertTrue(textColor == "#ffffff" || textColor == "#111111", "\(palette.name)'s text colors are all either white or black")
            }
        }
    }

    // The user hand-specified this exact pattern (white for every note except A/E/B, which get
    // black) — not something `legibleTextColors(for:)` is expected to reproduce on its own, so
    // this is pinned literally rather than re-derived from `PitchClassPalette.hex`.
    func testDefaultPaletteTextColorsMatchHandSpecifiedPattern() {
        let palette = ColorPalette.builtInDefaults[0]
        XCTAssertEqual(palette.name, "Default")
        // index: 0=C 1=Db 2=D 3=Eb 4=E 5=F 6=F# 7=G 8=Ab 9=A 10=Bb 11=B
        let expected = [
            "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#111111", "#ffffff",
            "#ffffff", "#ffffff", "#ffffff", "#111111", "#ffffff", "#111111",
        ]
        XCTAssertEqual(palette.textColors, expected, "Default's text colors are white except A(9)/E(4)/B(11), which are black")
    }

    func testLegibleTextColorsUsesYIQBrightnessThreshold() {
        let textColors = ColorPalette.legibleTextColors(for: ["#ffffff", "#000000", "#ffe119"])
        XCTAssertEqual(textColors, ["#111111", "#ffffff", "#111111"])
    }

    func testSessionStartsWithDefaultPaletteMatchingPitchClassPalette() {
        let session = ImprovSession()
        XCTAssertEqual(session.colorPalettes.count, 1, "a fresh session starts with exactly one (fallback) palette")
        XCTAssertEqual(session.activeColorPalette.name, "Default")
        XCTAssertEqual(session.activeColorPalette.colors, PitchClassPalette.hex)
    }

    func testMigrateColorPalettesSeedsBuiltInDefaultsOnFirstRunThenIsIdempotent() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let schema = Schema([ColorPaletteRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))

        let session = ImprovSession(modelContainer: container)
        session.migrateColorPalettesFromJSONIfNeeded(fromJSONFile: tempFile.path)
        XCTAssertEqual(session.colorPalettes, ColorPalette.builtInDefaults)
        XCTAssertEqual(session.activeColorPalette.name, "Default")

        // A second session sharing the SAME store must load what's already there, not re-seed.
        try session.selectColorPalette(named: "Pastel")
        let reloaded = ImprovSession(modelContainer: container)
        reloaded.migrateColorPalettesFromJSONIfNeeded(fromJSONFile: tempFile.path)
        XCTAssertEqual(reloaded.colorPalettes, ColorPalette.builtInDefaults, "migrateColorPalettesFromJSONIfNeeded doesn't re-seed an already-populated store")
    }

    func testMigrateSpectrogramSettingsSeedsDefaultsThenPersistsChanges() throws {
        let schema = Schema([SpectrogramSettingsRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))

        let session = ImprovSession(modelContainer: container)
        session.migrateSpectrogramSettingsFromJSONIfNeeded(fromJSONFile: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json").path)
        XCTAssertEqual(session.spectrogramSettings.palette, "thermal")
        XCTAssertFalse(session.spectrogramSettings.showNoteOverlay)

        try session.setSpectrogramPalette("blue")
        try session.setSpectrogramShowNoteOverlay(true)
        XCTAssertEqual(session.spectrogramSettings.palette, "blue")
        XCTAssertTrue(session.spectrogramSettings.showNoteOverlay)

        // A second session sharing the SAME store must see the persisted change.
        let reloaded = ImprovSession(modelContainer: container)
        reloaded.migrateSpectrogramSettingsFromJSONIfNeeded(fromJSONFile: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json").path)
        XCTAssertEqual(reloaded.spectrogramSettings.palette, "blue")
        XCTAssertTrue(reloaded.spectrogramSettings.showNoteOverlay)
    }

    func testSelectColorPaletteByNameAndIndexAndRejectsInvalid() throws {
        let session = makeTestSession()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        session.migrateColorPalettesFromJSONIfNeeded(fromJSONFile: tempFile.path)

        try session.selectColorPalette(named: "Contraste")
        XCTAssertEqual(session.activeColorPalette.name, "Contraste")

        try session.selectColorPalette(atIndex: 2)
        XCTAssertEqual(session.activeColorPalette.name, "Pastel", "selectColorPalette(atIndex:) is 0-based")

        XCTAssertThrowsError(try session.selectColorPalette(named: "Not A Real Palette")) { error in
            guard case ImprovSession.SessionError.invalidColorPaletteIndex = error else {
                return XCTFail("expected invalidColorPaletteIndex, got \(error)")
            }
        }
        XCTAssertThrowsError(try session.selectColorPalette(atIndex: 99)) { error in
            guard case ImprovSession.SessionError.invalidColorPaletteIndex = error else {
                return XCTFail("expected invalidColorPaletteIndex, got \(error)")
            }
        }
    }

    func testMigrateColorPalettesFallsBackToBuiltInsOnEmptyPalettesFile() throws {
        let schema = Schema([ColorPaletteRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let session = ImprovSession(modelContainer: container)
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try JSONEncoder().encode(ColorPaletteFile(palettes: [])).write(to: tempFile)

        // An empty (or otherwise unusable) `palettes.json` isn't treated as "nothing to
        // migrate, seed built-ins" being an error — migration never throws, same as every
        // other `migrate...FromJSONIfNeeded` in this file.
        session.migrateColorPalettesFromJSONIfNeeded(fromJSONFile: tempFile.path)
        XCTAssertEqual(session.colorPalettes, ColorPalette.builtInDefaults)
    }

    // MARK: - Sample folder: recursive subfolder scanning

    func testListSampleFilesRecursesIntoSubfoldersUsingRelativePaths() throws {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libFolder = folder.appendingPathComponent("OrchestralLib/Strings")
        try FileManager.default.createDirectory(at: libFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try Data().write(to: folder.appendingPathComponent("Piano.sf2"))
        try Data().write(to: libFolder.appendingPathComponent("Violin.sf2"))
        try Data().write(to: libFolder.appendingPathComponent("ReadMe.txt")) // not a sample extension

        try session.listSampleFiles(in: folder.path)

        XCTAssertEqual(session.sampleFiles, ["OrchestralLib/Strings/Violin.sf2", "Piano.sf2"])
    }

    func testLoadSampleResolvesARelativeSubfolderPath() throws {
        let session = ImprovSession()
        try session.start()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libFolder = folder.appendingPathComponent("Lib")
        try FileManager.default.createDirectory(at: libFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: libFolder.appendingPathComponent("Violin.sf2"))

        try session.listSampleFiles(in: folder.path)
        XCTAssertEqual(session.sampleFiles, ["Lib/Violin.sf2"])
        // An empty/garbage .sf2 fails to actually load as a sound bank, but the point here is
        // that the relative path resolves to the right file at all (a real load attempt, not a
        // silently-wrong path) — AVAudioUnitSampler throws on the malformed file, not on a
        // missing one.
        XCTAssertThrowsError(try session.loadSample(named: "Lib/Violin.sf2"))
    }

    // MARK: - SoundFont presets (multi-preset .sf2)

    func testSoundFontPresetsThrowsWhenNoSampleFolderListed() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.soundFontPresets(forPath: "Whatever.sf2"))
    }

    func testSoundFontPresetsResolvesRelativePathAndPropagatesReaderErrors() throws {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("Empty.sf2"))
        try session.listSampleFiles(in: folder.path)

        // Confirms `soundFontPresets(forPath:)` resolves against `sampleFolder` the same way
        // `loadSample(named:)` does, and surfaces the reader's own typed error rather than
        // swallowing or wrapping it.
        XCTAssertThrowsError(try session.soundFontPresets(forPath: "Empty.sf2")) { error in
            XCTAssertEqual(error as? SoundFontPresetReaderError, .truncatedData)
        }
    }

    func testSetInstrumentAcceptsAnOptionalPresetWithoutBreakingTheDefaultCase() throws {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("Empty.sf2"))
        try session.listSampleFiles(in: folder.path)

        // Same "malformed file still resolves to the right path and fails at load, not before"
        // shape as `testLoadSampleResolvesARelativeSubfolderPath`, for both the default (no
        // preset — unchanged behavior) and explicit-preset overloads of `setInstrument`.
        XCTAssertThrowsError(try session.setInstrument(named: "Empty.sf2", for: .computerKeyboard))
        XCTAssertThrowsError(try session.setInstrument(named: "Empty.sf2", for: .computerKeyboard, preset: SoundFontPresetIdentity(program: 5, bank: 0)))
    }

    // MARK: - Sound aliases & favorites

    /// Sets up an `ImprovSession` with an isolated temp folder standing in for the local-only
    /// soundfont folder `SoundFontLocations.localFolderURL()` would otherwise resolve to (the
    /// real `Application Support` — never touched by tests). `syncedFolder: nil` throughout:
    /// these tests only exercise local-only soundfonts, same as running with no iCloud account.
    /// `sourceFolder` is a SEPARATE temp directory for tests to write fake incoming `.sf2` files
    /// into before importing them — distinct from `localFolder` (the import destination) so
    /// `SoundFontLibrary.importFile`'s own "destination already occupied" rename logic never
    /// kicks in just because the fake source happened to already sit at its own destination
    /// path (a real import's source is wherever the user picked it from, never the destination
    /// folder itself).
    private func makeSoundFontTestSession() throws -> (session: ImprovSession, container: ModelContainer, localFolder: URL, sourceFolder: URL) {
        let schema = Schema([SoundEntryRecord.self, SoundFontRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let session = ImprovSession(modelContainer: container)
        let localFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: localFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        session.startSoundFontLibrary(syncedFolder: nil, localFolder: localFolder)
        return (session, container, localFolder, sourceFolder)
    }

    func testSetSoundAliasAndFavoritePersistAcrossSessionsSharingTheSameStore() throws {
        let (session, container, _, sourceFolder) = try makeSoundFontTestSession()
        // Distinct content per file: `SoundFontHasher` identifies a soundfont by its bytes, so
        // two empty files would collapse into the exact same hash/record — not what these
        // tests want to exercise (three separately favoritable/aliasable soundfonts).
        try Data([0x01]).write(to: sourceFolder.appendingPathComponent("Violin.sf2"))
        try Data([0x02]).write(to: sourceFolder.appendingPathComponent("Piano.sf2"))
        try Data([0x03]).write(to: sourceFolder.appendingPathComponent("Cello.sf2"))
        let violin = try session.importSoundFont(at: sourceFolder.appendingPathComponent("Violin.sf2"), syncPreference: .localOnly)
        let piano = try session.importSoundFont(at: sourceFolder.appendingPathComponent("Piano.sf2"), syncPreference: .localOnly)

        try session.setSoundAlias(forHash: violin.hash, alias: "Violon chaud")
        try session.setSoundFavorite(forHash: violin.hash, isFavorite: true)
        try session.setSoundFavorite(forHash: piano.hash, isFavorite: true)

        XCTAssertEqual(session.soundAlias(forHash: violin.hash), "Violon chaud")
        XCTAssertTrue(session.isSoundFavorite(forHash: violin.hash))
        XCTAssertTrue(session.isSoundFavorite(forHash: piano.hash))
        XCTAssertFalse(session.isSoundFavorite(forHash: "not-a-real-hash"))

        // A second session sharing the SAME model container must see the persisted entries —
        // `soundEntries` only actually reflects the store after some refresh call, same as
        // every other SwiftData-backed list in this class (nothing loads it eagerly at init).
        let reloaded = ImprovSession(modelContainer: container)
        reloaded.migrateSoundSettingsFromJSONIfNeeded(fromJSONFile: "/nonexistent-\(UUID()).json")
        XCTAssertEqual(reloaded.soundAlias(forHash: violin.hash), "Violon chaud")
        XCTAssertTrue(reloaded.isSoundFavorite(forHash: piano.hash))
    }

    func testCatalogUpdatesDetectsAnOlderInstalledVersion() throws {
        let (session, _, _, sourceFolder) = try makeSoundFontTestSession()
        try Data([0x09]).write(to: sourceFolder.appendingPathComponent("Old.sf2"))
        let installed = try session.importSoundFont(
            at: sourceFolder.appendingPathComponent("Old.sf2"), syncPreference: .localOnly,
            origin: .curated(sourceURL: URL(string: "https://example.com/old.sf2")!, catalogEntryId: "musescore-general", catalogVersion: "0.1")
        )

        let updates = session.catalogUpdates
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.installed.hash, installed.hash)
        XCTAssertEqual(updates.first?.latest.id, "musescore-general")
    }

    func testCatalogUpdatesIsEmptyWhenInstalledVersionMatchesTheCatalog() throws {
        let (session, _, _, sourceFolder) = try makeSoundFontTestSession()
        guard let latest = CuratedSoundFontCatalog.entries.first(where: { $0.id == "musescore-general" }) else {
            XCTFail("expected the musescore-general catalog entry to exist")
            return
        }
        try Data([0x0A]).write(to: sourceFolder.appendingPathComponent("Current.sf2"))
        _ = try session.importSoundFont(
            at: sourceFolder.appendingPathComponent("Current.sf2"), syncPreference: .localOnly,
            origin: .curated(sourceURL: latest.downloadURL, catalogEntryId: latest.id, catalogVersion: latest.version)
        )

        XCTAssertTrue(session.catalogUpdates.isEmpty)
    }

    func testCatalogUpdatesIgnoresUserImportedSoundfonts() throws {
        let (session, _, _, sourceFolder) = try makeSoundFontTestSession()
        try Data([0x0B]).write(to: sourceFolder.appendingPathComponent("Mine.sf2"))
        _ = try session.importSoundFont(at: sourceFolder.appendingPathComponent("Mine.sf2"), syncPreference: .localOnly)

        XCTAssertTrue(session.catalogUpdates.isEmpty)
    }

    func testFavoriteSoundsFiltersToFavoritesOnly() throws {
        let (session, _, localFolder, sourceFolder) = try makeSoundFontTestSession()
        try Data().write(to: sourceFolder.appendingPathComponent("Piano.sf2"))
        let piano = try session.importSoundFont(at: sourceFolder.appendingPathComponent("Piano.sf2"), syncPreference: .localOnly)

        XCTAssertEqual(session.favoriteSounds, [], "nothing favorited yet")

        try session.setSoundFavorite(forHash: piano.hash, isFavorite: true)
        XCTAssertEqual(session.favoriteSounds.map(\.path), [localFolder.appendingPathComponent("Piano.sf2").path])

        try session.setSoundFavorite(forHash: piano.hash, isFavorite: false)
        XCTAssertEqual(session.favoriteSounds, [])
    }

    func testFavoriteSoundsDistinguishesPresetsOfTheSameFile() throws {
        let (session, _, localFolder, sourceFolder) = try makeSoundFontTestSession()
        try Self.minimalSoundFont(presets: [
            (name: "Grand Piano", program: 0, bank: 0), (name: "Church Organ", program: 19, bank: 0),
        ]).write(to: sourceFolder.appendingPathComponent("GMBank.sf2"))
        let bank = try session.importSoundFont(at: sourceFolder.appendingPathComponent("GMBank.sf2"), syncPreference: .localOnly)

        let piano = SoundFontPresetIdentity(program: 0, bank: 0)
        let organ = SoundFontPresetIdentity(program: 19, bank: 0)
        try session.setSoundFavorite(forHash: bank.hash, preset: piano, isFavorite: true)
        try session.setSoundAlias(forHash: bank.hash, preset: organ, alias: "Orgue")
        try session.setSoundFavorite(forHash: bank.hash, preset: organ, isFavorite: true)

        let bankPath = localFolder.appendingPathComponent("GMBank.sf2").path
        XCTAssertEqual(Set(session.favoriteSounds.map(\.id)), [
            "\(bankPath)#0:0", "\(bankPath)#19:0",
        ])
        XCTAssertTrue(session.isSoundFavorite(forHash: bank.hash, preset: piano))
        XCTAssertFalse(session.isSoundFavorite(forHash: bank.hash), "the file's own default preset (nil) was never favorited, only program 0 explicitly")
        XCTAssertEqual(session.soundAlias(forHash: bank.hash, preset: organ), "Orgue")
        XCTAssertNil(session.soundAlias(forHash: bank.hash, preset: piano))
    }

    /// `favoriteSounds` must show "file — sound name" when no alias was set (the user's own
    /// explicit ask, 2026-07-27: a bare file/preset id isn't enough to recognize a favorite in
    /// a picker), and just the alias once one exists.
    func testFavoriteSoundsDisplayNameFallsBackToFileAndSoundNameWithoutAlias() throws {
        let (session, _, _, sourceFolder) = try makeSoundFontTestSession()
        try Self.minimalSoundFont(presets: [(name: "Grand Piano", program: 0, bank: 0)])
            .write(to: sourceFolder.appendingPathComponent("Bank.sf2"))
        let bank = try session.importSoundFont(at: sourceFolder.appendingPathComponent("Bank.sf2"), syncPreference: .localOnly)

        let piano = SoundFontPresetIdentity(program: 0, bank: 0)
        try session.setSoundFavorite(forHash: bank.hash, preset: piano, isFavorite: true)
        // `SoundFontEntry.displayName` defaults to the extension-stripped file name (see
        // `SoundFontLibrary.importFile`) — a deliberately friendlier default than the old
        // path-based system's bare "Bank.sf2", which never had a separate display name concept.
        XCTAssertEqual(session.favoriteSounds.first?.displayName, "Bank — Grand Piano")

        try session.setSoundAlias(forHash: bank.hash, preset: piano, alias: "Mon Piano")
        XCTAssertEqual(session.favoriteSounds.first?.displayName, "Mon Piano")
    }

    /// Minimal synthetic `.sf2` byte buffer (RIFF/`sfbk` -> `LIST pdta` -> `phdr`), same
    /// technique `SoundFontModelTests.SoundFontPresetReaderTests` uses — no real `.sf2` fixture
    /// is checked into the repo.
    private static func minimalSoundFont(presets: [(name: String, program: UInt16, bank: UInt16)]) -> Data {
        func uint16LE(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)] }
        func uint32LE(_ value: UInt32) -> [UInt8] {
            [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
        }
        func chunk(id: String, body: [UInt8]) -> [UInt8] {
            var bytes = Array(id.utf8) + uint32LE(UInt32(body.count)) + body
            if body.count % 2 == 1 { bytes.append(0) }
            return bytes
        }
        func phdrRecord(name: String, program: UInt16, bank: UInt16) -> [UInt8] {
            var nameBytes = Array(name.utf8.prefix(20))
            nameBytes += Array(repeating: UInt8(0), count: 20 - nameBytes.count)
            return nameBytes + uint16LE(program) + uint16LE(bank) + uint16LE(0) + uint32LE(0) + uint32LE(0) + uint32LE(0)
        }
        var phdrBody: [UInt8] = []
        for preset in presets { phdrBody += phdrRecord(name: preset.name, program: preset.program, bank: preset.bank) }
        phdrBody += phdrRecord(name: "EOP", program: 0, bank: 0)

        let pdtaBody = Array("pdta".utf8) + chunk(id: "phdr", body: phdrBody)
        let riffBody = Array("sfbk".utf8) + chunk(id: "LIST", body: pdtaBody)
        return Data(chunk(id: "RIFF", body: riffBody))
    }

    /// `displayName(forSamplePath:)` is the one remaining path-based accessor (still how
    /// `SceneRole.soundName` works — migrating scene roles to hash-based identity is a separate,
    /// explicitly out-of-scope follow-up) — it resolves the path's file name against the
    /// hash-indexed `soundFonts` library to find an alias, rather than storing anything by path
    /// itself.
    func testDisplayNameForSamplePathFallsBackToPathWithoutAlias() throws {
        let (session, _, _, sourceFolder) = try makeSoundFontTestSession()
        XCTAssertEqual(session.displayName(forSamplePath: "Piano.sf2"), "Piano.sf2", "no indexed soundfont named that yet")

        try Data().write(to: sourceFolder.appendingPathComponent("Piano.sf2"))
        let piano = try session.importSoundFont(at: sourceFolder.appendingPathComponent("Piano.sf2"), syncPreference: .localOnly)
        try session.setSoundAlias(forHash: piano.hash, alias: "  Piano chaud  ")

        XCTAssertEqual(session.displayName(forSamplePath: "Piano.sf2"), "Piano chaud", "alias is trimmed")
        XCTAssertEqual(session.displayName(forSamplePath: "SomeSubfolder/Piano.sf2"), "Piano chaud", "matches by file name alone, ignoring subfolders")
    }

    func testSettingAliasToEmptyOrFavoriteToFalseRemovesTheEntryEntirely() throws {
        let (session, _, _, _) = try makeSoundFontTestSession()

        try session.setSoundAlias(forHash: "hash-piano", alias: "Piano chaud")
        XCTAssertEqual(session.soundEntries.count, 1)
        try session.setSoundAlias(forHash: "hash-piano", alias: "")
        XCTAssertEqual(session.soundEntries.count, 0, "clearing the only field an entry had removes it")

        try session.setSoundFavorite(forHash: "hash-cello", isFavorite: true)
        XCTAssertEqual(session.soundEntries.count, 1)
        try session.setSoundFavorite(forHash: "hash-cello", isFavorite: false)
        XCTAssertEqual(session.soundEntries.count, 0)
    }

    /// Same as `makeSoundFontTestSession` but with a (temp-directory-backed) synced folder too,
    /// standing in for a real iCloud Drive container being available — needed to exercise
    /// `setSoundFontSyncPreference`'s `.localOnly` -> `.synced` direction, which
    /// `makeSoundFontTestSession`'s `syncedFolder: nil` can't (matches "no iCloud account").
    private func makeSoundFontTestSessionWithSyncedFolder() throws -> (session: ImprovSession, localFolder: URL, syncedFolder: URL, sourceFolder: URL) {
        let schema = Schema([SoundEntryRecord.self, SoundFontRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let session = ImprovSession(modelContainer: container)
        let localFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let syncedFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: localFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: syncedFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        session.startSoundFontLibrary(syncedFolder: syncedFolder, localFolder: localFolder)
        return (session, localFolder, syncedFolder, sourceFolder)
    }

    func testSetSoundFontSyncPreferenceMovesTheFileBetweenFolders() throws {
        let (session, localFolder, syncedFolder, sourceFolder) = try makeSoundFontTestSessionWithSyncedFolder()
        try Data([0x01]).write(to: sourceFolder.appendingPathComponent("Bank.sf2"))
        let imported = try session.importSoundFont(at: sourceFolder.appendingPathComponent("Bank.sf2"), syncPreference: .localOnly)
        XCTAssertTrue(FileManager.default.fileExists(atPath: localFolder.appendingPathComponent("Bank.sf2").path))

        let synced = try session.setSoundFontSyncPreference(hash: imported.hash, to: .synced)
        XCTAssertEqual(synced.syncPreference, .synced)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localFolder.appendingPathComponent("Bank.sf2").path), "moved out of local")
        XCTAssertTrue(FileManager.default.fileExists(atPath: syncedFolder.appendingPathComponent("Bank.sf2").path), "moved into synced")
        XCTAssertEqual(session.soundFonts.first { $0.hash == imported.hash }?.syncPreference, .synced)

        let backToLocal = try session.setSoundFontSyncPreference(hash: imported.hash, to: .localOnly)
        XCTAssertEqual(backToLocal.syncPreference, .localOnly)
        XCTAssertTrue(FileManager.default.fileExists(atPath: localFolder.appendingPathComponent("Bank.sf2").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: syncedFolder.appendingPathComponent("Bank.sf2").path))
    }

    func testSetSoundFontSyncPreferenceIsANoOpWhenAlreadyAtThatPreference() throws {
        let (session, _, _, sourceFolder) = try makeSoundFontTestSessionWithSyncedFolder()
        try Data([0x01]).write(to: sourceFolder.appendingPathComponent("Bank.sf2"))
        let imported = try session.importSoundFont(at: sourceFolder.appendingPathComponent("Bank.sf2"), syncPreference: .localOnly)

        let result = try session.setSoundFontSyncPreference(hash: imported.hash, to: .localOnly)
        XCTAssertEqual(result, imported)
    }

    func testSetSoundFontSyncPreferenceThrowsWhenTheSyncedFileIsntDownloadedHere() throws {
        let (session, _, syncedFolder, sourceFolder) = try makeSoundFontTestSessionWithSyncedFolder()
        try Data([0x01]).write(to: sourceFolder.appendingPathComponent("Bank.sf2"))
        let imported = try session.importSoundFont(at: sourceFolder.appendingPathComponent("Bank.sf2"), syncPreference: .synced)
        XCTAssertEqual(imported.syncPreference, .synced)

        // Simulate the file being evicted/not-yet-downloaded on this device (a real not-yet-
        // downloaded iCloud item behaves the same way from `FileManager`'s point of view: no
        // regular file at that path) — the index still knows about it, only the bytes are gone.
        try FileManager.default.removeItem(at: syncedFolder.appendingPathComponent("Bank.sf2"))

        XCTAssertThrowsError(try session.setSoundFontSyncPreference(hash: imported.hash, to: .localOnly)) { error in
            XCTAssertEqual(error as? SoundFontLibraryError, .notDownloadedOnThisDevice)
        }
    }
}

extension ImprovSession.SessionError: Equatable {
    // Compares by description rather than an exhaustive case-by-case switch, so adding a
    // new SessionError case doesn't also require updating this test helper.
    public static func == (lhs: ImprovSession.SessionError, rhs: ImprovSession.SessionError) -> Bool {
        lhs.description == rhs.description
    }
}

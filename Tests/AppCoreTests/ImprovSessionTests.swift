import XCTest
@testable import AppCore
@testable import PieceModel
import MIDIEngine
import MusicTheoryKit
import LLMEngine
import SoundTrackModel
import SoundFontModel
import AudioEngine

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

    func testListPieceFilesFindsJSONFilesAndIgnoresOthers() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("b.json"))
        try Data().write(to: folder.appendingPathComponent("a.json"))
        try Data().write(to: folder.appendingPathComponent("notes.txt"))

        let session = ImprovSession()
        try session.listPieceFiles(in: folder.path)
        XCTAssertEqual(session.pieceFiles, ["a.json", "b.json"])
        XCTAssertEqual(session.pieceFolder, folder.path)
    }

    func testUsePieceByIndexAndNameLoadFromTheListedFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let writer = ImprovSession()
        writer.loadDemoPiece()
        try writer.savePiece(toJSONFile: folder.appendingPathComponent("demo.json").path)

        let session = ImprovSession()
        try session.listPieceFiles(in: folder.path)
        try session.loadPiece(atIndex: 0)
        XCTAssertEqual(session.piece?.title, "ii-V-I demo")

        let byName = ImprovSession()
        try byName.listPieceFiles(in: folder.path)
        try byName.loadPiece(named: "demo.json")
        XCTAssertEqual(byName.piece?.title, "ii-V-I demo")
    }

    func testLoadPieceAtInvalidIndexThrows() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let session = ImprovSession()
        try session.listPieceFiles(in: folder.path)
        XCTAssertThrowsError(try session.loadPiece(atIndex: 0)) { error in
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

    func testSaveAsThenBareSaveRoundTripToTheSameFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let session = ImprovSession()
        session.loadDemoPiece()
        try session.listPieceFiles(in: folder.path) // establishes the working directory
        try session.savePiece(as: "my-piece") // bare name, ".json" added automatically

        let expectedPath = folder.appendingPathComponent("my-piece.json").path
        XCTAssertEqual(session.currentPieceFilePath, expectedPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath))

        // A bare `savePiece()` now re-saves to that same resolved path without error.
        try session.savePiece()
    }

    func testSaveAsWithExplicitPathIgnoresPieceFolder() throws {
        let explicitPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/nested/piece").path
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: explicitPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: URL(fileURLWithPath: explicitPath).deletingLastPathComponent().deletingLastPathComponent()) }

        let session = ImprovSession()
        session.loadDemoPiece()
        try session.savePiece(as: explicitPath) // contains "/", so used as-is (no pieceFolder needed)
        XCTAssertEqual(session.currentPieceFilePath, explicitPath + ".json")
    }

    func testSaveAsWithoutAPieceFolderListedThrowsForABareName() {
        let session = ImprovSession()
        session.loadDemoPiece()
        XCTAssertThrowsError(try session.savePiece(as: "my-piece")) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noPieceFolderListed)
        }
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
        let session = ImprovSession()
        try session.startTrack(.microphone)
        session.beginMicrophoneCalibrationCapture(phase: .quiet)
        session.simulateMicrophoneDetection([], level: 0.01, track: .microphone)
        session.simulateMicrophoneDetection([], level: 0.05, track: .microphone) // peak
        session.simulateMicrophoneDetection([], level: 0.02, track: .microphone) // lower again
        try session.endMicrophoneCalibrationCapture()
        XCTAssertEqual(session.microphoneCalibration.quietRMS, 0.05)
    }

    func testMicrophoneCalibrationCapturesThePeakLevelForTheLoudPhase() throws {
        let session = ImprovSession()
        try session.startTrack(.microphone)
        session.beginMicrophoneCalibrationCapture(phase: .loud)
        session.simulateMicrophoneDetection([], level: 0.2, track: .microphone)
        session.simulateMicrophoneDetection([], level: 0.4, track: .microphone) // peak
        try session.endMicrophoneCalibrationCapture()
        XCTAssertEqual(session.microphoneCalibration.loudRMS, 0.4)
    }

    func testCancellingMicrophoneCalibrationCaptureLeavesSettingsUnchanged() throws {
        let session = ImprovSession()
        try session.startTrack(.microphone)
        let before = session.microphoneCalibration
        session.beginMicrophoneCalibrationCapture(phase: .loud)
        session.simulateMicrophoneDetection([], level: 0.9, track: .microphone)
        session.cancelMicrophoneCalibrationCapture()
        try session.endMicrophoneCalibrationCapture() // no capture in progress: a no-op
        XCTAssertEqual(session.microphoneCalibration, before)
    }

    func testResetMicrophoneCalibrationRestoresDefaults() throws {
        let session = ImprovSession()
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
        let session = ImprovSession()
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
        XCTAssertNil(session.currentPieceFilePath)
    }

    func testSetSourceTextStoresItAndLogs() {
        let session = ImprovSession()
        session.setSourceText("Roses are red")
        XCTAssertEqual(session.sourceText, "Roses are red")
        XCTAssertTrue(session.log.contains { $0.contains("Source text set") })
    }

    func testListLLMConnectionsFindsJSONFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let connection = LLMConnection(name: "Local Ollama", provider: "ollama", baseURL: "http://localhost:11434", model: "llama3")
        try JSONEncoder().encode(connection).write(to: folder.appendingPathComponent("ollama.json"))
        try Data().write(to: folder.appendingPathComponent("notes.txt"))

        let session = ImprovSession()
        try session.listLLMConnections(in: folder.path)
        XCTAssertEqual(session.llmConnections, ["ollama.json"])
    }

    func testUseLLMConnectionByIndexAndNameLoadFromTheListedFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let connection = LLMConnection(name: "Local Ollama", provider: "ollama", baseURL: "http://localhost:11434", model: "llama3")
        try JSONEncoder().encode(connection).write(to: folder.appendingPathComponent("ollama.json"))

        let session = ImprovSession()
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)
        XCTAssertEqual(session.currentLLMConnection, connection)

        let byName = ImprovSession()
        try byName.listLLMConnections(in: folder.path)
        try byName.useLLMConnection(named: "ollama.json")
        XCTAssertEqual(byName.currentLLMConnection, connection)
    }

    func testComposeFromTextWithoutSourceTextThrows() throws {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "x", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("x.json"))
        try session.listLLMConnections(in: folder.path)
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

        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        try session.listLLMConnections(in: folder.path)
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
        XCTAssertNil(session.currentPieceFilePath)
    }

    func testComposeFromTextWithATitleOverridesTheLLMsOwnTitle() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        try session.listLLMConnections(in: folder.path)
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

        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        session.setAdditionalCompositionInstructions("romantique, mode mineur")
        try session.listLLMConnections(in: folder.path)
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

        let session = ImprovSession()
        session.setSourceText("a poem")
        try session.listLLMConnections(in: folder.path)
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

        let session = ImprovSession()
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)
        try session.listPieceFiles(in: folder.path) // establishes pieceFolder for saving candidates

        try session.startRecording(title: "ForCompose")
        session.pressKey(pitch: 62)
        session.releaseKey(pitch: 62)
        _ = try session.stopRecording()

        let fakeResponse = """
        { "title": "From Recording", "tempoBPM": 90, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        let paths = try session.composeSoundTrackToPieces(candidateCount: 1) { prompt, connection in
            XCTAssertTrue(prompt.contains("ON"))
            XCTAssertEqual(connection.name, "Fake")
            return fakeResponse
        }
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(session.piece?.title, "From Recording")
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths[0]))
    }

    func testComposeSoundTrackToPiecesWithATitleOverridesTheLLMsOwnTitle() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)
        try session.listPieceFiles(in: folder.path)
        try session.startRecording(title: "ForCompose")
        session.pressKey(pitch: 62)
        session.releaseKey(pitch: 62)
        _ = try session.stopRecording()

        let fakeResponse = """
        { "title": "LLM Chosen Title", "tempoBPM": 90, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        let paths = try session.composeSoundTrackToPieces(candidateCount: 1, title: "My Own Title") { _, _ in fakeResponse }

        XCTAssertEqual(session.piece?.title, "My Own Title")
        XCTAssertTrue(paths[0].hasSuffix("My Own Title.json"))
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
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        try session.setPromptsFolder(root.path)

        var isDirectory: ObjCBool = false
        for subfolder in ["Cadrage Composition Descriptive", "Cadrage Composition Soundtrack", "composition Descriptive", "Indications Soundtracks", "Export"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(subfolder).path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
        }
        XCTAssertEqual(session.textFramingFiles, [])
        XCTAssertEqual(session.soundTrackFramingFiles, [])
        XCTAssertEqual(session.soundTrackInstructionsFiles, [])
        // compositionFolder/compositionFiles are now derived from setPromptsFolder — no
        // separate listCompositionFiles(in:) call needed.
        XCTAssertEqual(session.compositionFolder, root.appendingPathComponent("composition Descriptive").path)
        XCTAssertEqual(session.compositionFiles, [])
    }

    func testExportTextCompositionPromptWritesCurrentPromptToExportSubfolder() throws {
        let session = ImprovSession()
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
        let session = ImprovSession()
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
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        XCTAssertNil(session.currentSoundTrackCompositionInstructions())

        session.setSoundTrackCompositionInstructions("romantique, mode mineur")
        try session.saveSoundTrackCompositionInstructions(as: "my-instructions")
        XCTAssertEqual(session.soundTrackInstructionsFiles, ["my-instructions.txt"])

        session.resetSoundTrackCompositionInstructions()
        XCTAssertNil(session.currentSoundTrackCompositionInstructions())

        try session.useSoundTrackCompositionInstructions(atIndex: 0)
        XCTAssertEqual(session.activeSoundTrackCompositionInstructions, "romantique, mode mineur")
    }

    func testSaveSoundTrackCompositionInstructionsWithoutAnySetThrows() throws {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        XCTAssertThrowsError(try session.saveSoundTrackCompositionInstructions(as: "nothing-to-save")) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noSoundTrackCompositionInstructions)
        }
    }

    func testUseSoundTrackCompositionInstructionsWithInvalidIndexThrows() throws {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
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
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        session.setTextFramingSentence("A distinctive custom framing sentence.")

        try session.saveTextFramingSentence(as: "my-framing")
        XCTAssertEqual(session.textFramingFiles, ["my-framing.txt"])

        session.resetTextFramingSentence()
        XCTAssertEqual(session.currentTextFramingSentence(), LLMPieceComposer.defaultTextFramingSentence)

        try session.useTextFramingSentence(atIndex: 0)
        XCTAssertEqual(session.activeTextFramingSentence, "A distinctive custom framing sentence.")
    }

    func testSaveAndUseSoundTrackFramingSentenceRoundTrips() throws {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        session.setSoundTrackFramingSentence("A distinctive soundtrack framing sentence.")

        try session.saveSoundTrackFramingSentence(as: "my-soundtrack-framing")
        XCTAssertEqual(session.soundTrackFramingFiles, ["my-soundtrack-framing.txt"])

        session.resetSoundTrackFramingSentence()
        try session.useSoundTrackFramingSentence(named: "my-soundtrack-framing.txt")
        XCTAssertEqual(session.activeSoundTrackFramingSentence, "A distinctive soundtrack framing sentence.")
    }

    func testUseTextFramingSentenceWithInvalidIndexThrows() throws {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        XCTAssertThrowsError(try session.useTextFramingSentence(atIndex: 0)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .invalidTextFramingIndex)
        }
    }

    // MARK: - Composition descriptions (save/load title+text+indications)

    func testSaveThenLoadCompositionDescriptionRoundTrips() throws {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try session.listCompositionFiles(in: folder.path)

        session.setCompositionTitle("My Ballad")
        session.setSourceText("a poem about the sea")
        session.setAdditionalCompositionInstructions("romantique, mode mineur")
        try session.saveCompositionDescription(as: "my-description")
        XCTAssertEqual(session.compositionFiles, ["my-description.json"])

        let reloaded = ImprovSession()
        try reloaded.listCompositionFiles(in: folder.path)
        try reloaded.loadCompositionDescription(atIndex: 0)
        XCTAssertEqual(reloaded.compositionTitle, "My Ballad")
        XCTAssertEqual(reloaded.sourceText, "a poem about the sea")
        XCTAssertEqual(reloaded.additionalCompositionInstructions, "romantique, mode mineur")
    }

    func testLoadCompositionDescriptionAtInvalidIndexThrows() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = ImprovSession()
        try session.listCompositionFiles(in: folder.path)
        XCTAssertThrowsError(try session.loadCompositionDescription(atIndex: 0)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .invalidCompositionIndex)
        }
    }

    func testSaveCompositionDescriptionWithoutSourceTextThrows() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.saveCompositionDescription(as: "/tmp/whatever")) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noSourceText)
        }
    }

    func testSaveCompositionDescriptionWithoutFolderListedThrows() {
        let session = ImprovSession()
        session.setSourceText("a poem")
        XCTAssertThrowsError(try session.saveCompositionDescription(as: "bare-name")) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noCompositionFolderListed)
        }
    }

    func testSaveCompositionDescriptionWithoutHavingSavedOnceThrows() {
        let session = ImprovSession()
        session.setSourceText("a poem")
        XCTAssertThrowsError(try session.saveCompositionDescription()) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noCurrentCompositionFile)
        }
    }

    func testSaveCompositionDescriptionReSavesToTheSameFile() throws {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try session.listCompositionFiles(in: folder.path)
        session.setSourceText("first version")
        try session.saveCompositionDescription(as: "iterate")

        session.setSourceText("second version")
        try session.saveCompositionDescription()

        let reloaded = ImprovSession()
        try reloaded.loadCompositionDescription(fromJSONFile: folder.appendingPathComponent("iterate.json").path)
        XCTAssertEqual(reloaded.sourceText, "second version")
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

    /// Regression test for a real bug surfaced during manual testing, suspected (correctly)
    /// to involve the per-role volume feature: picking a role's FIRST sound creates a brand
    /// new `SamplerUnit` inside `setInstrument`, which starts at full engine volume — before
    /// this fix, `setSceneRoleSound` never reapplied the role's own already-configured
    /// volume onto that fresh instance, so a role deliberately turned down (e.g. to avoid
    /// dominating the mix) would jump back to full volume the moment its sound was assigned.
    func testSetSceneRoleSoundReappliesRoleVolumeToAFreshlyCreatedSampler() throws {
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

        // Volume set BEFORE any sound exists on the track — no sampler to apply it to yet,
        // only recorded on the role itself.
        try session.setSceneRoleVolume(roleID, volume: 0.3)
        XCTAssertNil(session.samplerVolume(for: .computerKeyboard))

        try session.setSceneRoleSound(roleID, soundName: sampleName)
        XCTAssertEqual(session.samplerVolume(for: .computerKeyboard) ?? -1, 0.3, accuracy: 0.001)
    }

    func testTestSceneRoleSoundThrowsWithoutActiveScene() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.testSceneRoleSound(UUID())) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .noSceneLoaded)
        }
    }

    func testTestSceneRoleSoundThrowsForUnknownRole() throws {
        let session = ImprovSession()
        session.newScene(title: "Test")
        XCTAssertThrowsError(try session.testSceneRoleSound(UUID())) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .unknownSceneRole)
        }
    }

    func testTestSceneRoleSoundThrowsWhenRoleHasNoSoundAssigned() throws {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Test")
        let roleID = try session.addSceneRole(name: "Piano")

        // Unattached: nothing to test yet.
        XCTAssertThrowsError(try session.testSceneRoleSound(roleID)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .sceneRoleHasNoSoundToTest)
        }

        // Attached, but no sound ever assigned.
        try session.attachInstrument(.computerKeyboard, toRole: roleID)
        XCTAssertThrowsError(try session.testSceneRoleSound(roleID)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .sceneRoleHasNoSoundToTest)
        }
    }

    func testTestSceneRoleSoundPlaysThroughTheAttachedInstrumentsSampler() throws {
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

        // A demo note is deliberately not a real played note — must not touch heldPitches/
        // the recognizer, unlike `pressKey`.
        try session.testSceneRoleSound(roleID, duration: 0.01)
        XCTAssertTrue(session.tracks.first { $0.id == .computerKeyboard }?.heldPitches.isEmpty ?? false)
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

    func testLoadOrCreateLanguageSettingDefaultsToFrenchAndRoundTrips() throws {
        let session = ImprovSession()
        try session.start()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("language.json").path

        try session.loadOrCreateLanguageSetting(fromJSONFile: path)
        XCTAssertEqual(session.currentLanguage, .fr)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        // `setLanguage` only rewrites language.json once `settingsFolder` is set (mirrors
        // `selectColorPalette`'s "in-memory only" default, but this one also persists on change).
        try session.setSettingsFolder(folder.path)
        try session.setLanguage(.de)
        let reloaded = ImprovSession()
        try reloaded.start()
        try reloaded.loadLanguageSetting(fromJSONFile: path)
        XCTAssertEqual(reloaded.currentLanguage, .de)
    }

    func testSetLanguageUpdatesCurrentLanguageAndWebConsoleState() throws {
        let session = ImprovSession()
        try session.start()
        try session.setLanguage(.de)
        XCTAssertEqual(session.currentLanguage, .de)
        XCTAssertEqual(session.buildWebConsoleState().language, "de")
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

    func testLoadOrCreateColorPalettesWritesBuiltInDefaultsOnFirstRunThenLoadsThem() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path))

        let session = ImprovSession()
        try session.loadOrCreateColorPalettes(fromJSONFile: tempFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path))
        XCTAssertEqual(session.colorPalettes, ColorPalette.builtInDefaults)
        XCTAssertEqual(session.activeColorPalette.name, "Default")

        // A second session pointed at the SAME (now-existing) file must not overwrite it —
        // only ever create it once.
        try session.selectColorPalette(named: "Pastel")
        let reloaded = ImprovSession()
        try reloaded.loadOrCreateColorPalettes(fromJSONFile: tempFile.path)
        XCTAssertEqual(reloaded.colorPalettes, ColorPalette.builtInDefaults, "loadOrCreateColorPalettes doesn't overwrite an existing file")
    }

    func testLoadOrCreateSpectrogramSettingsWritesDefaultsThenPersistsChanges() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path))

        let session = ImprovSession()
        try session.loadOrCreateSpectrogramSettings(fromJSONFile: tempFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path))
        XCTAssertEqual(session.spectrogramSettings.palette, "thermal")
        XCTAssertFalse(session.spectrogramSettings.showNoteOverlay)

        // `setSpectrogramPalette`/`setSpectrogramShowNoteOverlay` only persist once a settings
        // folder is known (see `setSettingsFolder`) — exercised end to end via that, not the
        // bare JSON file, same convention as the Lumi/palette settings.
        let settingsFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: settingsFolder) }
        try session.setSettingsFolder(settingsFolder.path)
        try session.setSpectrogramPalette("blue")
        try session.setSpectrogramShowNoteOverlay(true)
        XCTAssertEqual(session.spectrogramSettings.palette, "blue")
        XCTAssertTrue(session.spectrogramSettings.showNoteOverlay)

        let reloaded = ImprovSession()
        try reloaded.setSettingsFolder(settingsFolder.path)
        XCTAssertEqual(reloaded.spectrogramSettings.palette, "blue")
        XCTAssertTrue(reloaded.spectrogramSettings.showNoteOverlay)
    }

    func testSelectColorPaletteByNameAndIndexAndRejectsInvalid() throws {
        let session = ImprovSession()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.loadOrCreateColorPalettes(fromJSONFile: tempFile.path)

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

    func testLoadColorPalettesThrowsOnEmptyPalettesFile() throws {
        let session = ImprovSession()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try JSONEncoder().encode(ColorPaletteFile(palettes: [])).write(to: tempFile)
        XCTAssertThrowsError(try session.loadColorPalettes(fromJSONFile: tempFile.path)) { error in
            guard case ImprovSession.SessionError.emptyColorPaletteFile = error else {
                return XCTFail("expected emptyColorPaletteFile, got \(error)")
            }
        }
        // The previous (fallback) palette must still be there — a failed load shouldn't
        // have cleared anything.
        XCTAssertEqual(session.colorPalettes.count, 1)
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

    func testSetSoundAliasAndFavoritePersistToSoundSettingsFile() throws {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try session.setSettingsFolder(folder.path)

        try session.setSoundAlias("OrchestralLib/Strings/Violin.sf2", alias: "Violon chaud")
        try session.setSoundFavorite("OrchestralLib/Strings/Violin.sf2", isFavorite: true)
        try session.setSoundFavorite("Piano.sf2", isFavorite: true)

        XCTAssertEqual(session.soundAlias(forPath: "OrchestralLib/Strings/Violin.sf2"), "Violon chaud")
        XCTAssertTrue(session.isSoundFavorite("OrchestralLib/Strings/Violin.sf2"))
        XCTAssertTrue(session.isSoundFavorite("Piano.sf2"))
        XCTAssertFalse(session.isSoundFavorite("Cello.sf2"))

        let reloaded = ImprovSession()
        try reloaded.setSettingsFolder(folder.path)
        XCTAssertEqual(reloaded.soundAlias(forPath: "OrchestralLib/Strings/Violin.sf2"), "Violon chaud")
        XCTAssertTrue(reloaded.isSoundFavorite("Piano.sf2"))
    }

    func testFavoriteSoundsFiltersSampleFilesToFavoritesOnly() throws {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("Piano.sf2"))
        try Data().write(to: folder.appendingPathComponent("Cello.sf2"))
        try session.listSampleFiles(in: folder.path)
        try session.setSettingsFolder(folder.appendingPathComponent("Settings").path)

        XCTAssertEqual(session.favoriteSounds, [], "nothing favorited yet")

        try session.setSoundFavorite("Piano.sf2", isFavorite: true)
        XCTAssertEqual(session.favoriteSounds.map(\.path), ["Piano.sf2"])

        try session.setSoundFavorite("Piano.sf2", isFavorite: false)
        XCTAssertEqual(session.favoriteSounds, [])
    }

    func testFavoriteSoundsDistinguishesPresetsOfTheSameFile() throws {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("GMBank.sf2"))
        try session.listSampleFiles(in: folder.path)
        try session.setSettingsFolder(folder.appendingPathComponent("Settings").path)

        let piano = SoundFontPresetIdentity(program: 0, bank: 0)
        let organ = SoundFontPresetIdentity(program: 19, bank: 0)
        try session.setSoundFavorite("GMBank.sf2", preset: piano, isFavorite: true)
        try session.setSoundAlias("GMBank.sf2", preset: organ, alias: "Orgue")
        try session.setSoundFavorite("GMBank.sf2", preset: organ, isFavorite: true)

        XCTAssertEqual(Set(session.favoriteSounds.map(\.id)), [
            "GMBank.sf2#0:0", "GMBank.sf2#19:0",
        ])
        XCTAssertTrue(session.isSoundFavorite("GMBank.sf2", preset: piano))
        XCTAssertFalse(session.isSoundFavorite("GMBank.sf2"), "the file's own default preset (nil) was never favorited, only program 0 explicitly")
        XCTAssertEqual(session.soundAlias(forPath: "GMBank.sf2", preset: organ), "Orgue")
        XCTAssertNil(session.soundAlias(forPath: "GMBank.sf2", preset: piano))
    }

    /// `favoriteSounds` must show "file — sound name" when no alias was set (the user's own
    /// explicit ask, 2026-07-27: a bare file/preset id isn't enough to recognize a favorite in
    /// a picker), and just the alias once one exists.
    func testFavoriteSoundsDisplayNameFallsBackToFileAndSoundNameWithoutAlias() throws {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Self.minimalSoundFont(presets: [(name: "Grand Piano", program: 0, bank: 0)])
            .write(to: folder.appendingPathComponent("Bank.sf2"))
        try session.listSampleFiles(in: folder.path)
        try session.setSettingsFolder(folder.appendingPathComponent("Settings").path)

        let piano = SoundFontPresetIdentity(program: 0, bank: 0)
        try session.setSoundFavorite("Bank.sf2", preset: piano, isFavorite: true)
        XCTAssertEqual(session.favoriteSounds.first?.displayName, "Bank.sf2 — Grand Piano")

        try session.setSoundAlias("Bank.sf2", preset: piano, alias: "Mon Piano")
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

    func testDisplayNameForSamplePathFallsBackToPathWithoutAlias() throws {
        let session = ImprovSession()
        XCTAssertEqual(session.displayName(forSamplePath: "Piano.sf2"), "Piano.sf2")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try session.setSettingsFolder(folder.path)
        try session.setSoundAlias("Piano.sf2", alias: "  Piano chaud  ")
        XCTAssertEqual(session.displayName(forSamplePath: "Piano.sf2"), "Piano chaud", "alias is trimmed")
    }

    func testSettingAliasToEmptyOrFavoriteToFalseRemovesTheEntryEntirely() throws {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try session.setSettingsFolder(folder.path)

        try session.setSoundAlias("Piano.sf2", alias: "Piano chaud")
        XCTAssertEqual(session.soundEntries.count, 1)
        try session.setSoundAlias("Piano.sf2", alias: "")
        XCTAssertEqual(session.soundEntries.count, 0, "clearing the only field an entry had removes it")

        try session.setSoundFavorite("Cello.sf2", isFavorite: true)
        XCTAssertEqual(session.soundEntries.count, 1)
        try session.setSoundFavorite("Cello.sf2", isFavorite: false)
        XCTAssertEqual(session.soundEntries.count, 0)
    }
}

extension ImprovSession.SessionError: Equatable {
    // Compares by description rather than an exhaustive case-by-case switch, so adding a
    // new SessionError case doesn't also require updating this test helper.
    public static func == (lhs: ImprovSession.SessionError, rhs: ImprovSession.SessionError) -> Bool {
        lhs.description == rhs.description
    }
}

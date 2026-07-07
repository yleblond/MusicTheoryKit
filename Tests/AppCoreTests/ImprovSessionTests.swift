import XCTest
@testable import AppCore
@testable import PieceModel
import MIDIEngine
import MusicTheoryKit
import LLMEngine
import SoundTrackModel

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

    func testStartTrackOnAnUnlistedMIDIPortThrows() {
        let session = ImprovSession()
        // Default fusion mode is `.merged`, so `.midiSource(0)` isn't one of `tracks` yet.
        XCTAssertThrowsError(try session.startTrack(.midiSource(0))) { error in
            guard case .unknownTrack = error as? ImprovSession.SessionError else {
                XCTFail("expected .unknownTrack, got \(error)")
                return
            }
        }
    }

    func testDefaultMIDIFusionModeIsMergedWithASingleMIDITrack() {
        let session = ImprovSession()
        XCTAssertEqual(session.midiFusionMode, .merged)
        XCTAssertTrue(session.tracks.contains { $0.id == .midiMerged })
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

    func testMicrophoneTrackCannotHaveSound() {
        let session = ImprovSession()
        XCTAssertThrowsError(try session.setSoundEnabled(true, for: .microphone)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .trackCannotHaveSound)
        }
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

    func testSetPromptsFolderCreatesBothSubfoldersAndListsFiles() throws {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        try session.setPromptsFolder(root.path)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Texte").path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Soundtrack").path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(session.textPromptFiles, [])
        XCTAssertEqual(session.soundTrackPromptFiles, [])
    }

    func testSaveAndUseTextCompositionPromptRoundTrips() throws {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        session.setSourceText("a poem about the sea")

        try session.saveTextCompositionPrompt(as: "my-prompt")
        XCTAssertEqual(session.textPromptFiles, ["my-prompt.txt"])

        session.setSourceText("a totally different poem")
        XCTAssertNil(session.activeTextCompositionPrompt)
        try session.useTextCompositionPrompt(atIndex: 0)
        XCTAssertTrue(session.activeTextCompositionPrompt?.contains("a poem about the sea") ?? false)
        // The active override, not the (now different) sourceText, is what gets used.
        XCTAssertTrue((try session.currentTextCompositionPrompt()).contains("a poem about the sea"))

        session.resetTextCompositionPrompt()
        XCTAssertNil(session.activeTextCompositionPrompt)
        XCTAssertTrue((try session.currentTextCompositionPrompt()).contains("a totally different poem"))
    }

    func testSaveAndUseSoundTrackCompositionPromptRoundTrips() throws {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        try session.startRecording(title: "ForPrompt")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()

        try session.saveSoundTrackCompositionPrompt(as: "my-soundtrack-prompt")
        XCTAssertEqual(session.soundTrackPromptFiles, ["my-soundtrack-prompt.txt"])

        try session.useSoundTrackCompositionPrompt(named: "my-soundtrack-prompt.txt")
        XCTAssertNotNil(session.activeSoundTrackCompositionPrompt)

        session.resetSoundTrackCompositionPrompt()
        XCTAssertNil(session.activeSoundTrackCompositionPrompt)
    }

    func testUseTextCompositionPromptWithInvalidIndexThrows() throws {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        XCTAssertThrowsError(try session.useTextCompositionPrompt(atIndex: 0)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .invalidTextPromptIndex)
        }
    }

    func testComposeFromTextUsesTheActiveOverridePromptVerbatim() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)
        try session.setPromptsFolder(folder.path)
        session.setSourceText("ignored once a prompt override is active")
        try session.saveTextCompositionPrompt(as: "custom")
        session.setSourceText("also ignored")
        try session.useTextCompositionPrompt(named: "custom.txt")

        let fakeResponse = """
        { "title": "Override", "tempoBPM": 90, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        try session.composeFromText { prompt, _ in
            XCTAssertTrue(prompt.contains("ignored once a prompt override is active"))
            XCTAssertFalse(prompt.contains("also ignored"))
            return fakeResponse
        }
        XCTAssertEqual(session.piece?.title, "Override")
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
}

extension ImprovSession.SessionError: Equatable {
    // Compares by description rather than an exhaustive case-by-case switch, so adding a
    // new SessionError case doesn't also require updating this test helper.
    public static func == (lhs: ImprovSession.SessionError, rhs: ImprovSession.SessionError) -> Bool {
        lhs.description == rhs.description
    }
}

import XCTest
@testable import AppCore
@testable import PieceModel
import MIDIEngine
import MusicTheoryKit
import LLMEngine

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
}

extension ImprovSession.SessionError: Equatable {
    // Compares by description rather than an exhaustive case-by-case switch, so adding a
    // new SessionError case doesn't also require updating this test helper.
    public static func == (lhs: ImprovSession.SessionError, rhs: ImprovSession.SessionError) -> Bool {
        lhs.description == rhs.description
    }
}

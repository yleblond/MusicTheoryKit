import XCTest
@testable import AppCore
@testable import PieceModel
import MIDIEngine
import MusicTheoryKit

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

    func testHandlingIncomingMIDIEventsDetectsChordWhileListenOnly() throws {
        let session = ImprovSession()
        // `listenOnly: true` so this never touches the (unstarted) audio engine.
        try session.startListening(listenOnly: true)
        for pitch in [60, 64, 67, 71] { // C E G B -> Cmaj7
            session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: pitch, velocity: 100, channel: 0))
        }
        XCTAssertEqual(session.recognizedChord?.root, PitchClass(0))
        XCTAssertEqual(session.recognizedChord?.chordTemplateID, "Ma7")
        session.stopListening()
        XCTAssertNil(session.recognizedChord)
    }

    func testStartListeningWithoutListenOnlySoundsTheNote() throws {
        let session = ImprovSession()
        try session.start() // needed before player.startNote is exercised below
        try session.startListening(listenOnly: false)
        // Just verifying this doesn't throw/crash when routed to the (now-started) sampler.
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0))
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOff, pitch: 60, velocity: 0, channel: 0))
    }
}

extension ImprovSession.SessionError: Equatable {
    public static func == (lhs: ImprovSession.SessionError, rhs: ImprovSession.SessionError) -> Bool {
        switch (lhs, rhs) {
        case (.noPieceLoaded, .noPieceLoaded): return true
        }
    }
}

import XCTest
@testable import AppCore

/// Session-level integration tests for `ImprovSession.importScore(at:)` — the whole
/// SMFReader -> RawScoreComposer -> `piece` pipeline, exercised the same way a real
/// `.fileImporter` pick would (a real file on disk, not an in-memory `RawScore`).
final class ScoreImportSessionTests: XCTestCase {
    /// A minimal, valid single-track format-1 SMF: one measure of a C major triad at 120 BPM,
    /// hand-built the same way `SMFReaderTests`' fixtures are (this target can't share that
    /// target's private helpers, so a small standalone builder lives here instead).
    private func makeMinimalMIDIFile() -> Data {
        func vlq(_ value: Int) -> [UInt8] {
            var buffer = [UInt8](); var v = value & 0x7F; var remaining = value >> 7
            buffer.append(UInt8(v))
            while remaining > 0 { v = remaining & 0x7F; remaining >>= 7; buffer.insert(UInt8(v) | 0x80, at: 0) }
            return buffer
        }
        func u16(_ value: Int) -> [UInt8] { [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
        func u32(_ value: Int) -> [UInt8] { [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
        func chunk(_ id: String, _ payload: [UInt8]) -> [UInt8] { Array(id.utf8) + u32(payload.count) + payload }

        let track: [UInt8] =
            vlq(0) + [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20] + // tempo: 500000us/quarter = 120 BPM
            vlq(0) + [0xFF, 0x58, 0x04, 4, 2, 0x18, 0x08] + // time sig 4/4
            vlq(0) + [0x90, 60, 100] + // note-on C4
            vlq(0) + [0x90, 64, 100] + // note-on E4 (running status)
            vlq(0) + [0x90, 67, 100] + // note-on G4 (running status)
            vlq(1920) + [0x80, 60, 0] + // note-off C4 after one measure (4 * 480 ticks)
            vlq(0) + [0x80, 64, 0] +
            vlq(0) + [0x80, 67, 0] +
            vlq(0) + [0xFF, 0x2F, 0x00] // end of track

        let bytes = chunk("MThd", u16(1) + u16(1) + u16(480)) + chunk("MTrk", track)
        return Data(bytes)
    }

    private func writeTempMIDIFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mid")
        try makeMinimalMIDIFile().write(to: url)
        return url
    }

    func testImportScoreWithUnsupportedExtensionThrows() throws {
        let session = makeTestSession()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try session.importScore(at: url)) { error in
            XCTAssertEqual(error as? ImprovSession.SessionError, .unsupportedScoreFileExtension("pdf"))
        }
    }

    func testImportMusicXMLFileProducesAPlayablePiece() throws {
        let session = makeTestSession()
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part-list><score-part id="P1"><part-name>Melody</part-name></score-part></part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>
              <note><pitch><step>C</step><alter>0</alter><octave>4</octave></pitch><duration>1</duration></note>
              <note><pitch><step>E</step><alter>0</alter><octave>4</octave></pitch><duration>1</duration></note>
              <note><pitch><step>G</step><alter>0</alter><octave>4</octave></pitch><duration>2</duration></note>
            </measure>
          </part>
        </score-partwise>
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).musicxml")
        try Data(xml.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try session.importScore(at: url)

        let piece = try XCTUnwrap(session.piece)
        XCTAssertEqual(piece.sections.count, 1)
        XCTAssertEqual(piece.sections[0].tracks[0].melodyEvents.count, 3)
    }

    func testImportMuseScoreFileProducesAPlayablePiece() throws {
        let session = makeTestSession()
        let mscx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <museScore version="4.20">
          <Score>
            <Staff id="1">
              <Measure>
                <voice>
                  <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
                  <Chord><durationType>quarter</durationType><Note><pitch>60</pitch><tpc>14</tpc></Note></Chord>
                  <Chord><durationType>quarter</durationType><Note><pitch>64</pitch><tpc>18</tpc></Note></Chord>
                  <Chord><durationType>half</durationType><Note><pitch>67</pitch><tpc>15</tpc></Note></Chord>
                </voice>
              </Measure>
            </Staff>
          </Score>
        </museScore>
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mscx")
        try Data(mscx.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try session.importScore(at: url)

        let piece = try XCTUnwrap(session.piece)
        XCTAssertEqual(piece.sections.count, 1)
        XCTAssertEqual(piece.sections[0].tracks[0].melodyEvents.count, 3)
    }

    func testImportMIDIFileProducesAPlayablePieceNamedAfterTheFile() throws {
        let session = makeTestSession()
        let url = try writeTempMIDIFile()
        defer { try? FileManager.default.removeItem(at: url) }

        try session.importScore(at: url)

        let piece = try XCTUnwrap(session.piece)
        XCTAssertEqual(piece.title, url.deletingPathExtension().lastPathComponent)
        XCTAssertEqual(piece.tempoBPM, 120, accuracy: 0.01)
        XCTAssertEqual(piece.sections.count, 1)
        XCTAssertEqual(piece.sections[0].tracks.count, 1)
        XCTAssertEqual(piece.sections[0].tracks[0].melodyEvents.count, 3)
        XCTAssertNil(session.currentPieceRecordID) // not yet saved, same as a freshly-composed piece
    }

    func testImportEmptyMIDIFileThrowsScoreImportFailed() throws {
        let session = makeTestSession()
        func u16(_ value: Int) -> [UInt8] { [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
        func u32(_ value: Int) -> [UInt8] { [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
        func chunk(_ id: String, _ payload: [UInt8]) -> [UInt8] { Array(id.utf8) + u32(payload.count) + payload }
        let emptyTrack: [UInt8] = [0x00, 0xFF, 0x2F, 0x00]
        let bytes = chunk("MThd", u16(1) + u16(1) + u16(480)) + chunk("MTrk", emptyTrack)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mid")
        try Data(bytes).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try session.importScore(at: url)) { error in
            guard case .scoreImportFailed = error as? ImprovSession.SessionError else {
                return XCTFail("expected .scoreImportFailed, got \(error)")
            }
        }
    }
}

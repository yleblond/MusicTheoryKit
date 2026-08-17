import XCTest
@testable import ScoreImport

final class MuseScoreReaderTests: XCTestCase {
    private func wrap(voiceContent: String) -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <museScore version="4.20">
          <Score>
            <metaTag name="workTitle">Test Piece</metaTag>
            <metaTag name="composer">Test Composer</metaTag>
            <Part>
              <Staff id="1"/>
              <trackName>Piano</trackName>
            </Part>
            <Staff id="1">
              <Measure>
                <voice>
                  <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
                  <KeySig><concertKey>-1</concertKey></KeySig>
                  \(voiceContent)
                </voice>
              </Measure>
            </Staff>
          </Score>
        </museScore>
        """
        return Data(xml.utf8)
    }

    func testSingleNoteWithSpellingAndTrackName() throws {
        let data = wrap(voiceContent: """
        <Chord>
          <durationType>quarter</durationType>
          <Note><pitch>61</pitch><tpc>9</tpc></Note>
        </Chord>
        """)

        let score = try MuseScoreReader.parse(data: data)
        XCTAssertEqual(score.sourceFormat, .museScore)
        XCTAssertEqual(score.title, "Test Piece")
        XCTAssertEqual(score.composer, "Test Composer")
        XCTAssertEqual(score.parts.count, 1)
        XCTAssertEqual(score.parts[0].name, "Piano")

        let note = try XCTUnwrap(score.parts[0].notes.first)
        XCTAssertEqual(note.startTick, 0)
        XCTAssertEqual(note.durationTicks, 480)
        XCTAssertEqual(note.pitch, 61)
        XCTAssertEqual(note.spelling, RawSpelling(step: "D", alter: -1, octave: 4)) // tpc 9 = Db

        XCTAssertEqual(score.keySignatureMap, [RawKeySignatureEvent(tick: 0, fifths: -1, isMinor: false)])
        XCTAssertEqual(score.timeSignatureMap, [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)])
    }

    func testRestAdvancesTheCursor() throws {
        let data = wrap(voiceContent: """
        <Rest><durationType>quarter</durationType></Rest>
        <Chord><durationType>quarter</durationType><Note><pitch>62</pitch><tpc>16</tpc></Note></Chord>
        """)

        let score = try MuseScoreReader.parse(data: data)
        let notes = score.parts[0].notes
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes[0].isRest)
        XCTAssertEqual(notes[0].startTick, 0)
        XCTAssertFalse(notes[1].isRest)
        XCTAssertEqual(notes[1].startTick, 480)
    }

    func testChordGroupsMultipleSimultaneousNotes() throws {
        let data = wrap(voiceContent: """
        <Chord>
          <durationType>quarter</durationType>
          <Note><pitch>60</pitch><tpc>14</tpc></Note>
          <Note><pitch>64</pitch><tpc>18</tpc></Note>
          <Note><pitch>67</pitch><tpc>15</tpc></Note>
        </Chord>
        """)

        let score = try MuseScoreReader.parse(data: data)
        let notes = score.parts[0].notes
        XCTAssertEqual(notes.map(\.startTick), [0, 0, 0])
        XCTAssertEqual(Set(notes.map(\.pitch)), [60, 64, 67])
    }

    func testDottedDurationAddsHalfTheBaseValue() throws {
        let data = wrap(voiceContent: """
        <Chord>
          <durationType>quarter</durationType>
          <dots>1</dots>
          <Note><pitch>60</pitch><tpc>14</tpc></Note>
        </Chord>
        <Chord><durationType>eighth</durationType><Note><pitch>62</pitch><tpc>16</tpc></Note></Chord>
        """)

        let score = try MuseScoreReader.parse(data: data)
        let notes = score.parts[0].notes
        XCTAssertEqual(notes[0].durationTicks, 720) // dotted quarter = 1.5 * 480
        XCTAssertEqual(notes[1].startTick, 720)
    }

    func testMeasureBoundaryAdvancesByTheDeclaredTimeSignature() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <museScore version="4.20">
          <Score>
            <Staff id="1">
              <Measure>
                <voice>
                  <TimeSig><sigN>3</sigN><sigD>4</sigD></TimeSig>
                  <Chord><durationType>quarter</durationType><Note><pitch>60</pitch><tpc>14</tpc></Note></Chord>
                </voice>
              </Measure>
              <Measure>
                <voice>
                  <Chord><durationType>quarter</durationType><Note><pitch>62</pitch><tpc>16</tpc></Note></Chord>
                </voice>
              </Measure>
            </Staff>
          </Score>
        </museScore>
        """
        let score = try MuseScoreReader.parse(data: Data(xml.utf8))
        let notes = score.parts[0].notes
        XCTAssertEqual(notes[0].startTick, 0)
        XCTAssertEqual(notes[1].startTick, 1440) // measure 1 is a full 3/4 bar (3 * 480) regardless of how much of it note content filled
    }

    func testHarmonyBecomesAnExplicitChordSymbol() throws {
        let data = wrap(voiceContent: """
        <Harmony><root>14</root><name>Cmaj7</name></Harmony>
        <Chord><durationType>quarter</durationType><Note><pitch>60</pitch><tpc>14</tpc></Note></Chord>
        """)

        let score = try MuseScoreReader.parse(data: data)
        XCTAssertEqual(score.explicitChords, [RawChordSymbol(tick: 0, rootStep: "C", rootAlter: 0, kind: "Cmaj7")])
    }

    func testUnsupportedMajorVersionIsRejected() {
        let xml = "<museScore version=\"1.14\"><Score></Score></museScore>"
        XCTAssertThrowsError(try MuseScoreReader.parse(data: Data(xml.utf8))) { error in
            XCTAssertEqual(error as? MuseScoreReader.MuseScoreError, .unsupportedSchemaVersion("1.14"))
        }
    }

    /// MuseScore 2.x has no `<voice>` wrapper at all (unlike 4.x) — a measure's content sits
    /// directly under `<Measure>`. Verified against a real 2.06 file (`an-die-musik.mscz`,
    /// version "2.06") during this session; this is a synthetic regression guard for the same
    /// shape.
    func testVersion2SchemaWithoutAVoiceWrapperParsesCorrectly() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <museScore version="2.06">
          <Score>
            <Staff id="1">
              <Measure number="1">
                <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
                <Chord><durationType>quarter</durationType><Note><pitch>60</pitch><tpc>14</tpc></Note></Chord>
                <Rest><durationType>measure</durationType><duration z="4" n="4"/></Rest>
              </Measure>
            </Staff>
          </Score>
        </museScore>
        """
        let score = try MuseScoreReader.parse(data: Data(xml.utf8))
        let notes = score.parts[0].notes
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].startTick, 0)
        XCTAssertFalse(notes[0].isRest)
        XCTAssertEqual(notes[1].startTick, 480)
        XCTAssertTrue(notes[1].isRest)
        XCTAssertEqual(notes[1].durationTicks, 1920) // a 4/4 whole-measure rest via <duration z="4" n="4"/>
    }

    /// A staff-level `<Staff id="2">` starting right after another one's content must not carry
    /// over the previous staff's tick cursor — a real bug found against `an-die-musik.mscz`
    /// (a 3-staff score: voice, piano upper, piano lower).
    func testSecondStaffCursorDoesNotCarryOverFromTheFirst() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <museScore version="4.20">
          <Score>
            <Staff id="1">
              <Measure>
                <voice>
                  <Chord><durationType>whole</durationType><Note><pitch>60</pitch><tpc>14</tpc></Note></Chord>
                </voice>
              </Measure>
            </Staff>
            <Staff id="2">
              <Measure>
                <voice>
                  <Chord><durationType>quarter</durationType><Note><pitch>48</pitch><tpc>14</tpc></Note></Chord>
                </voice>
              </Measure>
            </Staff>
          </Score>
        </museScore>
        """
        let score = try MuseScoreReader.parse(data: Data(xml.utf8))
        let secondStaffNotes = try XCTUnwrap(score.parts.first { $0.id == "2" }).notes
        XCTAssertEqual(secondStaffNotes.first?.startTick, 0)
    }

    func testPlainRepeatDuplicatesTheEnclosedMeasures() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <museScore version="4.20">
          <Score>
            <Staff id="1">
              <Measure>
                <voice>
                  <TimeSig><sigN>1</sigN><sigD>4</sigD></TimeSig>
                  <startRepeat/>
                  <Chord><durationType>quarter</durationType><Note><pitch>60</pitch><tpc>14</tpc></Note></Chord>
                </voice>
              </Measure>
              <Measure>
                <voice>
                  <Chord><durationType>quarter</durationType><Note><pitch>62</pitch><tpc>16</tpc></Note></Chord>
                  <endRepeat>2</endRepeat>
                </voice>
              </Measure>
              <Measure>
                <voice>
                  <Chord><durationType>quarter</durationType><Note><pitch>64</pitch><tpc>18</tpc></Note></Chord>
                </voice>
              </Measure>
            </Staff>
          </Score>
        </museScore>
        """
        let score = try MuseScoreReader.parse(data: Data(xml.utf8))
        let notes = score.parts[0].notes
        XCTAssertEqual(notes.map(\.pitch), [60, 62, 60, 62, 64])
        XCTAssertEqual(notes.map(\.startTick), [0, 480, 960, 1440, 1920])
    }

    func testCompressedMSCZRoundTrips() throws {
        let mscx = wrap(voiceContent: "<Chord><durationType>quarter</durationType><Note><pitch>69</pitch><tpc>17</tpc></Note></Chord>")

        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func u32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)] }

        let name = "Test Piece.mscx"
        let content = Array(mscx)
        let nameBytes = Array(name.utf8)
        let local = u32(0x0403_4B50) + u16(20) + u16(0) + u16(0) + u16(0) + u16(0) + u32(0) + u32(content.count) + u32(content.count) + u16(nameBytes.count) + u16(0) + nameBytes + content
        let centralOffset = local.count
        let central = u32(0x0201_4B50) + u16(20) + u16(20) + u16(0) + u16(0) + u16(0) + u16(0) + u32(0) + u32(content.count) + u32(content.count)
            + u16(nameBytes.count) + u16(0) + u16(0) + u16(0) + u16(0) + u32(0) + u32(0) + nameBytes
        let eocd = u32(0x0605_4B50) + u16(0) + u16(0) + u16(1) + u16(1) + u32(central.count) + u32(centralOffset) + u16(0)
        let mscz = Data(local + central + eocd)

        let score = try MuseScoreReader.parse(data: mscz)
        XCTAssertEqual(score.parts[0].notes.first?.pitch, 69)
    }
}

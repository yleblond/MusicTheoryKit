import XCTest
@testable import ScoreImport

final class MusicXMLReaderTests: XCTestCase {
    private func wrap(partContent: String, divisions: Int = 24) -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <work><work-title>Test Piece</work-title></work>
          <identification><creator type="composer">Test Composer</creator></identification>
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes>
                <divisions>\(divisions)</divisions>
                <key><fifths>2</fifths><mode>major</mode></key>
                <time><beats>4</beats><beat-type>4</beat-type></time>
              </attributes>
              \(partContent)
            </measure>
          </part>
        </score-partwise>
        """
        return Data(xml.utf8)
    }

    func testSingleNoteWithSpellingAndVoiceStaff() throws {
        let data = wrap(partContent: """
        <note>
          <pitch><step>C</step><alter>1</alter><octave>4</octave></pitch>
          <duration>24</duration>
          <voice>1</voice>
          <staff>1</staff>
        </note>
        """)

        let score = try MusicXMLReader.parse(data: data)
        XCTAssertEqual(score.sourceFormat, .musicXML)
        XCTAssertEqual(score.title, "Test Piece")
        XCTAssertEqual(score.composer, "Test Composer")
        XCTAssertEqual(score.parts.count, 1)
        XCTAssertEqual(score.parts[0].name, "Piano")

        let note = try XCTUnwrap(score.parts[0].notes.first)
        XCTAssertEqual(note.startTick, 0)
        XCTAssertEqual(note.durationTicks, 480) // 24 divisions rescaled to the shared 480-tick-per-quarter output
        XCTAssertEqual(note.pitch, 61) // C#4
        XCTAssertEqual(note.spelling, RawSpelling(step: "C", alter: 1, octave: 4))
        XCTAssertEqual(note.voice, 1)
        XCTAssertEqual(note.staff, 1)
        XCTAssertFalse(note.isRest)

        XCTAssertEqual(score.keySignatureMap, [RawKeySignatureEvent(tick: 0, fifths: 2, isMinor: false)])
        XCTAssertEqual(score.timeSignatureMap, [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)])
    }

    func testRestAdvancesCursorWithoutAPitch() throws {
        let data = wrap(partContent: """
        <note><rest/><duration>24</duration></note>
        <note><pitch><step>D</step><alter>0</alter><octave>4</octave></pitch><duration>24</duration></note>
        """)

        let score = try MusicXMLReader.parse(data: data)
        let notes = score.parts[0].notes
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes[0].isRest)
        XCTAssertEqual(notes[0].startTick, 0)
        XCTAssertFalse(notes[1].isRest)
        XCTAssertEqual(notes[1].startTick, 480) // after the rest's full duration
        XCTAssertEqual(notes[1].pitch, 62) // D4
    }

    func testChordNoteSharesThePreviousNotesStartTick() throws {
        let data = wrap(partContent: """
        <note><pitch><step>C</step><alter>0</alter><octave>4</octave></pitch><duration>24</duration></note>
        <note><chord/><pitch><step>E</step><alter>0</alter><octave>4</octave></pitch><duration>24</duration></note>
        <note><chord/><pitch><step>G</step><alter>0</alter><octave>4</octave></pitch><duration>24</duration></note>
        <note><pitch><step>C</step><alter>0</alter><octave>5</octave></pitch><duration>24</duration></note>
        """)

        let score = try MusicXMLReader.parse(data: data)
        let notes = score.parts[0].notes
        XCTAssertEqual(notes.map(\.startTick), [0, 0, 0, 480])
        XCTAssertEqual(notes.map(\.pitch), [60, 64, 67, 72])
    }

    func testTieStartAndStop() throws {
        let data = wrap(partContent: """
        <note><pitch><step>C</step><alter>0</alter><octave>4</octave></pitch><duration>24</duration><tie type="start"/></note>
        <note><pitch><step>C</step><alter>0</alter><octave>4</octave></pitch><duration>24</duration><tie type="stop"/></note>
        """)

        let score = try MusicXMLReader.parse(data: data)
        let notes = score.parts[0].notes
        XCTAssertEqual(notes[0].tieStart, true)
        XCTAssertEqual(notes[0].tieStop, false)
        XCTAssertEqual(notes[1].tieStart, false)
        XCTAssertEqual(notes[1].tieStop, true)
    }

    func testBackupRewindsCursorForASecondVoice() throws {
        let data = wrap(partContent: """
        <note><pitch><step>C</step><alter>0</alter><octave>5</octave></pitch><duration>48</duration><voice>1</voice></note>
        <backup><duration>48</duration></backup>
        <note><pitch><step>C</step><alter>0</alter><octave>3</octave></pitch><duration>24</duration><voice>2</voice></note>
        <note><pitch><step>C</step><alter>0</alter><octave>3</octave></pitch><duration>24</duration><voice>2</voice></note>
        """)

        let score = try MusicXMLReader.parse(data: data)
        let notes = score.parts[0].notes
        let voice1 = notes.filter { $0.voice == 1 }
        let voice2 = notes.filter { $0.voice == 2 }
        XCTAssertEqual(voice1.map(\.startTick), [0])
        XCTAssertEqual(voice2.map(\.startTick), [0, 480]) // backed up to 0, then advances independently
    }

    func testHarmonyBecomesAnExplicitChordSymbol() throws {
        let data = wrap(partContent: """
        <harmony>
          <root><root-step>C</root-step><root-alter>0</root-alter></root>
          <kind text="Cmaj7">major-seventh</kind>
        </harmony>
        <note><pitch><step>C</step><alter>0</alter><octave>4</octave></pitch><duration>24</duration></note>
        """)

        let score = try MusicXMLReader.parse(data: data)
        XCTAssertEqual(score.explicitChords, [RawChordSymbol(tick: 0, rootStep: "C", rootAlter: 0, kind: "major-seventh")])
    }

    func testPlainRepeatDuplicatesTheEnclosedMeasures() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part-list><score-part id="P1"><part-name>Melody</part-name></score-part></part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>1</divisions><time><beats>1</beats><beat-type>4</beat-type></time></attributes>
              <barline location="left"><repeat direction="forward"/></barline>
              <note><pitch><step>C</step><alter>0</alter><octave>4</octave></pitch><duration>1</duration></note>
            </measure>
            <measure number="2">
              <barline location="right"><repeat direction="backward"/></barline>
              <note><pitch><step>D</step><alter>0</alter><octave>4</octave></pitch><duration>1</duration></note>
            </measure>
            <measure number="3">
              <note><pitch><step>E</step><alter>0</alter><octave>4</octave></pitch><duration>1</duration></note>
            </measure>
          </part>
        </score-partwise>
        """
        let score = try MusicXMLReader.parse(data: Data(xml.utf8))
        let notes = score.parts[0].notes
        // Measures 1-2 (C, D) play twice before measure 3 (E) — no `times` attribute defaults to 2 total plays.
        XCTAssertEqual(notes.map(\.pitch), [60, 62, 60, 62, 64])
        XCTAssertEqual(notes.map(\.startTick), [0, 480, 960, 1440, 1920])
    }

    func testRepeatWithExplicitTimesPlaysThatManyTimesTotal() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part-list><score-part id="P1"><part-name>Melody</part-name></score-part></part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>
              <note><pitch><step>C</step><alter>0</alter><octave>4</octave></pitch><duration>4</duration></note>
              <barline location="right"><repeat direction="backward" times="3"/></barline>
            </measure>
          </part>
        </score-partwise>
        """
        let score = try MusicXMLReader.parse(data: Data(xml.utf8))
        // No forward marker -> repeats from the start of the piece; times="3" -> 3 total plays.
        XCTAssertEqual(score.parts[0].notes.map(\.pitch), [60, 60, 60])
    }

    func testScoreTimewiseIsRejected() {
        let data = Data("<score-timewise version=\"3.1\"></score-timewise>".utf8)
        XCTAssertThrowsError(try MusicXMLReader.parse(data: data)) { error in
            XCTAssertEqual(error as? MusicXMLReader.MusicXMLError, .unsupportedDocumentType("score-timewise"))
        }
    }

    func testCompressedMXLRoundTrips() throws {
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container><rootfiles><rootfile full-path="score.xml" media-type="application/vnd.recordare.musicxml+xml"/></rootfiles></container>
        """
        let scoreXML = String(data: wrap(partContent: "<note><pitch><step>A</step><alter>0</alter><octave>4</octave></pitch><duration>24</duration></note>"), encoding: .utf8)!

        // Build the .mxl archive with the exact same hand-rolled byte-construction convention
        // `ZipArchiveReaderTests` uses (deliberately not reusing `ZipArchiveReader` itself here —
        // this test is about `MusicXMLReader`'s consumption of a real archive, not re-testing
        // the archive reader).
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func u32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)] }

        var body: [UInt8] = []
        var central: [UInt8] = []
        for (name, content) in [("META-INF/container.xml", Array(container.utf8)), ("score.xml", Array(scoreXML.utf8))] {
            let nameBytes = Array(name.utf8)
            let offset = body.count
            body += u32(0x0403_4B50) + u16(20) + u16(0) + u16(0) + u16(0) + u16(0) + u32(0) + u32(content.count) + u32(content.count) + u16(nameBytes.count) + u16(0) + nameBytes + content
            central += u32(0x0201_4B50) + u16(20) + u16(20) + u16(0) + u16(0) + u16(0) + u16(0) + u32(0) + u32(content.count) + u32(content.count)
                + u16(nameBytes.count) + u16(0) + u16(0) + u16(0) + u16(0) + u32(0) + u32(offset) + nameBytes
        }
        let centralOffset = body.count
        let eocd = u32(0x0605_4B50) + u16(0) + u16(0) + u16(2) + u16(2) + u32(central.count) + u32(centralOffset) + u16(0)
        let mxl = Data(body + central + eocd)

        let score = try MusicXMLReader.parse(data: mxl)
        XCTAssertEqual(score.parts[0].notes.first?.pitch, 69) // A4
    }
}

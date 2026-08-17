import XCTest
@testable import ScoreImport

final class SMFReaderTests: XCTestCase {
    // MARK: - Byte-building helpers (deliberately independent of SMFReader's own reading code)

    private func vlq(_ value: Int) -> [UInt8] {
        var buffer = [UInt8]()
        var v = value & 0x7F
        var remaining = value >> 7
        buffer.append(UInt8(v))
        while remaining > 0 {
            v = remaining & 0x7F
            remaining >>= 7
            buffer.insert(UInt8(v) | 0x80, at: 0)
        }
        return buffer
    }

    private func u16(_ value: Int) -> [UInt8] { [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
    private func u32(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
    private func chunk(_ id: String, _ payload: [UInt8]) -> [UInt8] {
        Array(id.utf8) + u32(payload.count) + payload
    }
    private func endOfTrack() -> [UInt8] { [0x00, 0xFF, 0x2F, 0x00] }
    private func tempoMeta(delta: Int, microsecondsPerQuarter: Int) -> [UInt8] {
        vlq(delta) + [0xFF, 0x51, 0x03] +
            [UInt8((microsecondsPerQuarter >> 16) & 0xFF), UInt8((microsecondsPerQuarter >> 8) & 0xFF), UInt8(microsecondsPerQuarter & 0xFF)]
    }
    private func timeSigMeta(delta: Int, beatsPerMeasure: Int, beatUnit: Int) -> [UInt8] {
        let denominatorExp = Int(log2(Double(beatUnit)))
        return vlq(delta) + [0xFF, 0x58, 0x04, UInt8(beatsPerMeasure), UInt8(denominatorExp), 0x18, 0x08]
    }
    private func noteOn(delta: Int, channel: Int, pitch: Int, velocity: Int, running: Bool = false) -> [UInt8] {
        vlq(delta) + (running ? [] : [UInt8(0x90 | channel)]) + [UInt8(pitch), UInt8(velocity)]
    }
    private func noteOff(delta: Int, channel: Int, pitch: Int, running: Bool = false, viaNoteOnZeroVelocity: Bool = false) -> [UInt8] {
        if viaNoteOnZeroVelocity {
            return vlq(delta) + (running ? [] : [UInt8(0x90 | channel)]) + [UInt8(pitch), 0x00]
        }
        return vlq(delta) + (running ? [] : [UInt8(0x80 | channel)]) + [UInt8(pitch), 0x40]
    }

    private func makeFile(format: Int, division: Int = 480, tracks: [[UInt8]]) -> Data {
        var bytes = chunk("MThd", u16(format) + u16(tracks.count) + u16(division))
        for track in tracks { bytes += chunk("MTrk", track) }
        return Data(bytes)
    }

    // MARK: - Tests

    func testSingleNoteRoundTrip() throws {
        let track =
            tempoMeta(delta: 0, microsecondsPerQuarter: 500_000) +
            timeSigMeta(delta: 0, beatsPerMeasure: 4, beatUnit: 4) +
            noteOn(delta: 0, channel: 0, pitch: 60, velocity: 100) +
            noteOff(delta: 480, channel: 0, pitch: 60) +
            endOfTrack()

        let score = try SMFReader.parse(data: makeFile(format: 1, tracks: [track]))

        XCTAssertEqual(score.divisionsPerQuarterNote, 480)
        XCTAssertEqual(score.tempoMap.first?.beatsPerMinute, 120)
        XCTAssertEqual(score.timeSignatureMap.first?.beatsPerMeasure, 4)
        XCTAssertEqual(score.timeSignatureMap.first?.beatUnit, 4)
        XCTAssertEqual(score.parts.count, 1)
        XCTAssertEqual(score.parts[0].notes.count, 1)
        let note = try XCTUnwrap(score.parts[0].notes.first)
        XCTAssertEqual(note.startTick, 0)
        XCTAssertEqual(note.durationTicks, 480)
        XCTAssertEqual(note.pitch, 60)
        XCTAssertEqual(note.velocity, 100) // the note-ON's velocity, not the note-OFF's data byte
    }

    func testRunningStatusNoteOffViaZeroVelocity() throws {
        // note-on ch0 p60, then a running-status "note-off" (0x90 status omitted, velocity 0),
        // then a running-status note-on p64, then an explicit-status note-off for p64.
        let track =
            noteOn(delta: 0, channel: 0, pitch: 60, velocity: 100) +
            noteOff(delta: 240, channel: 0, pitch: 60, running: true, viaNoteOnZeroVelocity: true) +
            noteOn(delta: 0, channel: 0, pitch: 64, velocity: 90, running: true) +
            noteOff(delta: 240, channel: 0, pitch: 64) +
            endOfTrack()

        let score = try SMFReader.parse(data: makeFile(format: 1, tracks: [track]))

        XCTAssertEqual(score.parts.count, 1)
        let notes = score.parts[0].notes.sorted { $0.pitch < $1.pitch }
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].pitch, 60); XCTAssertEqual(notes[0].startTick, 0); XCTAssertEqual(notes[0].durationTicks, 240)
        XCTAssertEqual(notes[1].pitch, 64); XCTAssertEqual(notes[1].startTick, 240); XCTAssertEqual(notes[1].durationTicks, 240)
    }

    func testTempoChangeMidFile() throws {
        let track =
            tempoMeta(delta: 0, microsecondsPerQuarter: 500_000) + // 120 BPM at tick 0
            noteOn(delta: 0, channel: 0, pitch: 60, velocity: 100) +
            tempoMeta(delta: 480, microsecondsPerQuarter: 400_000) + // 150 BPM at tick 480
            noteOff(delta: 0, channel: 0, pitch: 60) +
            endOfTrack()

        let score = try SMFReader.parse(data: makeFile(format: 1, tracks: [track]))

        XCTAssertEqual(score.tempoMap.count, 2)
        XCTAssertEqual(score.tempoMap[0].tick, 0)
        XCTAssertEqual(score.tempoMap[0].beatsPerMinute, 120)
        XCTAssertEqual(score.tempoMap[1].tick, 480)
        XCTAssertEqual(score.tempoMap[1].beatsPerMinute, 150)
    }

    func testFormat0SplitsByChannel() throws {
        // Format 0: exactly one track, channels interleaved.
        let track =
            noteOn(delta: 0, channel: 0, pitch: 60, velocity: 100) +
            noteOn(delta: 0, channel: 1, pitch: 40, velocity: 90) +
            noteOff(delta: 480, channel: 0, pitch: 60) +
            noteOff(delta: 0, channel: 1, pitch: 40) +
            endOfTrack()

        let score = try SMFReader.parse(data: makeFile(format: 0, tracks: [track]))

        XCTAssertEqual(score.parts.count, 2)
        let channel1 = try XCTUnwrap(score.parts.first { $0.name == "Channel 1" })
        let channel2 = try XCTUnwrap(score.parts.first { $0.name == "Channel 2" })
        XCTAssertEqual(channel1.notes.first?.pitch, 60)
        XCTAssertEqual(channel2.notes.first?.pitch, 40)
    }

    func testSimultaneousChordNotesAllRetained() throws {
        let track =
            noteOn(delta: 0, channel: 0, pitch: 60, velocity: 100, running: false) +
            noteOn(delta: 0, channel: 0, pitch: 64, velocity: 100, running: true) +
            noteOn(delta: 0, channel: 0, pitch: 67, velocity: 100, running: true) +
            noteOff(delta: 480, channel: 0, pitch: 60, running: false) +
            noteOff(delta: 0, channel: 0, pitch: 64, running: true) +
            noteOff(delta: 0, channel: 0, pitch: 67, running: true) +
            endOfTrack()

        let score = try SMFReader.parse(data: makeFile(format: 1, tracks: [track]))

        XCTAssertEqual(score.parts.count, 1)
        let notes = score.parts[0].notes.sorted { $0.pitch < $1.pitch }
        XCTAssertEqual(notes.map(\.pitch), [60, 64, 67])
        XCTAssertTrue(notes.allSatisfy { $0.startTick == 0 && $0.durationTicks == 480 })
    }

    func testOverlappingSamePitchNotesFIFOPairing() throws {
        // Two overlapping note-ons for the same pitch before either is closed — a FIFO
        // (not single-slot) open-note table must pair them start-order with close-order.
        let track =
            noteOn(delta: 0, channel: 0, pitch: 60, velocity: 100) +
            noteOn(delta: 10, channel: 0, pitch: 60, velocity: 100) +
            noteOff(delta: 10, channel: 0, pitch: 60) + // closes the tick-0 note at tick 20
            noteOff(delta: 10, channel: 0, pitch: 60) + // closes the tick-10 note at tick 30
            endOfTrack()

        let score = try SMFReader.parse(data: makeFile(format: 1, tracks: [track]))

        let notes = score.parts[0].notes.sorted { $0.startTick < $1.startTick }
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].startTick, 0); XCTAssertEqual(notes[0].durationTicks, 20)
        XCTAssertEqual(notes[1].startTick, 10); XCTAssertEqual(notes[1].durationTicks, 20)
    }

    func testTrackNameBecomesPartName() throws {
        let trackNameBytes = Array("Lead Guitar".utf8)
        let track =
            vlq(0) + [0xFF, 0x03, UInt8(trackNameBytes.count)] + trackNameBytes +
            noteOn(delta: 0, channel: 0, pitch: 60, velocity: 100) +
            noteOff(delta: 480, channel: 0, pitch: 60) +
            endOfTrack()

        let score = try SMFReader.parse(data: makeFile(format: 1, tracks: [track]))

        XCTAssertEqual(score.parts.first?.name, "Lead Guitar")
    }

    func testProgramChangeBecomesInstrumentHint() throws {
        let track =
            vlq(0) + [UInt8(0xC0), 0x28] + // program change, channel 0, program 40 = "Violin"
            noteOn(delta: 0, channel: 0, pitch: 60, velocity: 100) +
            noteOff(delta: 480, channel: 0, pitch: 60) +
            endOfTrack()

        let score = try SMFReader.parse(data: makeFile(format: 1, tracks: [track]))

        XCTAssertEqual(score.parts.first?.instrumentHint, "Violin")
    }

    func testUnsupportedFormat2Throws() {
        let bytes = chunk("MThd", u16(2) + u16(1) + u16(480)) + chunk("MTrk", endOfTrack())
        XCTAssertThrowsError(try SMFReader.parse(data: Data(bytes))) { error in
            XCTAssertEqual(error as? SMFReader.SMFError, .unsupportedFormat(2))
        }
    }

    func testMultiTrackFormat1() throws {
        let track1 =
            tempoMeta(delta: 0, microsecondsPerQuarter: 500_000) +
            noteOn(delta: 0, channel: 0, pitch: 72, velocity: 100) +
            noteOff(delta: 240, channel: 0, pitch: 72) +
            endOfTrack()
        let track2 =
            noteOn(delta: 0, channel: 1, pitch: 36, velocity: 100) +
            noteOff(delta: 480, channel: 1, pitch: 36) +
            endOfTrack()

        let score = try SMFReader.parse(data: makeFile(format: 1, tracks: [track1, track2]))

        XCTAssertEqual(score.parts.count, 2)
        XCTAssertEqual(score.parts[0].notes.first?.pitch, 72)
        XCTAssertEqual(score.parts[1].notes.first?.pitch, 36)
        XCTAssertEqual(score.tempoMap.count, 1) // meta events collected across all tracks
    }
}

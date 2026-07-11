import XCTest
@testable import MIDIEngine

final class MIDIRawParserTests: XCTestCase {

    func testParsesNoteOn() {
        let events = MIDIRawParser.parseNoteEvents([0x90, 60, 100])
        XCTAssertEqual(events, [MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0)])
    }

    func testParsesNoteOnOnNonZeroChannel() {
        let events = MIDIRawParser.parseNoteEvents([0x93, 60, 100])
        XCTAssertEqual(events, [MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 3)])
    }

    func testParsesNoteOff() {
        let events = MIDIRawParser.parseNoteEvents([0x80, 60, 0])
        XCTAssertEqual(events, [MIDINoteEvent(kind: .noteOff, pitch: 60, velocity: 0, channel: 0)])
    }

    func testNoteOnWithZeroVelocityIsTreatedAsNoteOff() {
        let events = MIDIRawParser.parseNoteEvents([0x90, 60, 0])
        XCTAssertEqual(events, [MIDINoteEvent(kind: .noteOff, pitch: 60, velocity: 0, channel: 0)])
    }

    func testParsesMultipleMessagesInOneBuffer() {
        let events = MIDIRawParser.parseNoteEvents([0x90, 60, 100, 0x90, 64, 90, 0x80, 60, 0])
        XCTAssertEqual(events, [
            MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0),
            MIDINoteEvent(kind: .noteOn, pitch: 64, velocity: 90, channel: 0),
            MIDINoteEvent(kind: .noteOff, pitch: 60, velocity: 0, channel: 0),
        ])
    }

    func testIgnoresNonNoteMessages() {
        // 0xB0 = control change (3 bytes), sandwiched between two note-ons.
        let events = MIDIRawParser.parseNoteEvents([0x90, 60, 100, 0xB0, 7, 127, 0x90, 64, 90])
        XCTAssertEqual(events, [
            MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0),
            MIDINoteEvent(kind: .noteOn, pitch: 64, velocity: 90, channel: 0),
        ])
    }

    func testTruncatedTrailingMessageIsDropped() {
        let events = MIDIRawParser.parseNoteEvents([0x90, 60, 100, 0x90, 64])
        XCTAssertEqual(events, [MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0)])
    }

    func testEmptyBufferProducesNoEvents() {
        XCTAssertEqual(MIDIRawParser.parseNoteEvents([]), [])
    }

    func testRunningStatusNoteOnIsParsedWithoutARepeatedStatusByte() {
        // Real note-on, then two more note-ons on the same channel with no repeated 0x90 —
        // exactly what a lot of real hardware sends for a fast chord/run.
        let events = MIDIRawParser.parseNoteEvents([0x90, 60, 100, 64, 90, 67, 80])
        XCTAssertEqual(events, [
            MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0),
            MIDINoteEvent(kind: .noteOn, pitch: 64, velocity: 90, channel: 0),
            MIDINoteEvent(kind: .noteOn, pitch: 67, velocity: 80, channel: 0),
        ])
    }

    func testRunningStatusNoteOffIsParsedWithoutARepeatedStatusByte() {
        // The bug this guards against: a running-status note-off used to be silently
        // dropped entirely (both its bytes are < 0x80), leaving the pitch stuck "held".
        let events = MIDIRawParser.parseNoteEvents([0x80, 60, 0, 64, 0])
        XCTAssertEqual(events, [
            MIDINoteEvent(kind: .noteOff, pitch: 60, velocity: 0, channel: 0),
            MIDINoteEvent(kind: .noteOff, pitch: 64, velocity: 0, channel: 0),
        ])
    }

    func testNonNoteStatusByteResetsRunningStatus() {
        // A control-change's own status byte (0xB0) shouldn't leave a stale note running
        // status in effect for the data bytes that follow a DIFFERENT message.
        let events = MIDIRawParser.parseNoteEvents([0x90, 60, 100, 0xB0, 7, 127])
        XCTAssertEqual(events, [MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0)])
    }
}

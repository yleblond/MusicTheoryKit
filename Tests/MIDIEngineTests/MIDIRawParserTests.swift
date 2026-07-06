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
}

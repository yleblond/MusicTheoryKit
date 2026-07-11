/// A decoded note on/off message, independent of any particular MIDI transport (CoreMIDI,
/// a file, a virtual keyboard...) so it can be tested and consumed without CoreMIDI.
public struct MIDINoteEvent: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case noteOn
        case noteOff
    }

    public var kind: Kind
    public var pitch: Int      // 0...127
    public var velocity: Int   // 0...127
    public var channel: Int    // 0...15

    public init(kind: Kind, pitch: Int, velocity: Int, channel: Int) {
        self.kind = kind
        self.pitch = pitch
        self.velocity = velocity
        self.channel = channel
    }
}

public enum MIDIRawParser {
    /// Decodes note on/off messages out of a raw MIDI byte stream (status byte first,
    /// as delivered in a `MIDIPacket`'s data). A note-on with velocity 0 is treated as a
    /// note-off, per the MIDI spec. Anything that isn't a note message (control change,
    /// sysex...) is skipped one byte at a time — sufficient for a plain keyboard's note
    /// stream, no attempt to skip a whole unsupported message at once.
    ///
    /// **Running status** for note on/off IS handled: real hardware (especially anything
    /// speaking true 5-pin-DIN MIDI rather than USB-MIDI class-compliant framing) commonly
    /// omits a repeated `0x90`/`0x80` status byte for consecutive note messages on the same
    /// channel, sending just the two data bytes and relying on the last real status byte
    /// still being in effect. Before this fix, `bytes[i] & 0x80 != 0` failed for those data
    /// bytes (both < 0x80), so the whole running-status note message was silently skipped —
    /// for a note-OFF specifically, that meant the pitch never left `heldPitches` and stayed
    /// stuck "held" until some later, unrelated note-off for the same pitch happened to fire
    /// (or never, if none did) — a real, reported "notes stay wrongly held" bug, not a
    /// theory. Any other (non note-on/off) status byte resets the running status, matching
    /// how real MIDI streams practically behave: a genuinely different message type almost
    /// always carries its own explicit status byte.
    public static func parseNoteEvents(_ bytes: [UInt8]) -> [MIDINoteEvent] {
        var events: [MIDINoteEvent] = []
        var i = 0
        var runningStatus: UInt8?
        while i < bytes.count {
            let byte = bytes[i]
            let status: UInt8
            let dataStart: Int
            if byte & 0x80 != 0 {
                status = byte
                dataStart = i + 1
            } else if let running = runningStatus {
                status = running
                dataStart = i
            } else {
                i += 1
                continue
            }
            let messageType = status & 0xF0
            guard messageType == 0x90 || messageType == 0x80 else {
                runningStatus = nil
                i += 1
                continue
            }
            runningStatus = status
            guard dataStart + 1 < bytes.count else { break }

            let channel = Int(status & 0x0F)
            let pitch = Int(bytes[dataStart])
            let velocity = Int(bytes[dataStart + 1])
            let kind: MIDINoteEvent.Kind = (messageType == 0x90 && velocity > 0) ? .noteOn : .noteOff
            events.append(MIDINoteEvent(kind: kind, pitch: pitch, velocity: velocity, channel: channel))
            i = dataStart + 2
        }
        return events
    }
}

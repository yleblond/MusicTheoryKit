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
    /// note-off, per the MIDI spec. Anything that isn't a 3-byte note message (control
    /// change, running status, sysex...) is skipped — sufficient for a plain keyboard's
    /// note stream; extend this if a source that relies on running status shows up.
    public static func parseNoteEvents(_ bytes: [UInt8]) -> [MIDINoteEvent] {
        var events: [MIDINoteEvent] = []
        var i = 0
        while i < bytes.count {
            let status = bytes[i]
            guard status & 0x80 != 0 else {
                i += 1
                continue
            }
            let messageType = status & 0xF0
            guard messageType == 0x90 || messageType == 0x80 else {
                i += 1
                continue
            }
            guard i + 2 < bytes.count else { break }

            let channel = Int(status & 0x0F)
            let pitch = Int(bytes[i + 1])
            let velocity = Int(bytes[i + 2])
            let kind: MIDINoteEvent.Kind = (messageType == 0x90 && velocity > 0) ? .noteOn : .noteOff
            events.append(MIDINoteEvent(kind: kind, pitch: pitch, velocity: velocity, channel: channel))
            i += 3
        }
        return events
    }
}

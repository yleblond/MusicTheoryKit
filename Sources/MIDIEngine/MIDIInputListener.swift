import CoreMIDI

public enum MIDIListenerError: Error {
    case clientCreationFailed(OSStatus)
    case portCreationFailed(OSStatus)
}

/// Listens to every currently-available CoreMIDI source (a physical keyboard, a virtual
/// port, an IAC bus...) and delivers decoded note events to `handler`. Distributing those
/// events to several consumers at once (audio, recognition, UI) is the caller's job —
/// this type only owns the CoreMIDI plumbing.
public final class MIDIInputListener {
    public typealias Handler = (MIDINoteEvent) -> Void

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private let handler: Handler

    public init(clientName: String = "MusicImprovAssistant", handler: @escaping Handler) throws {
        self.handler = handler

        var client = MIDIClientRef()
        let clientStatus = MIDIClientCreateWithBlock(clientName as CFString, &client, nil)
        guard clientStatus == noErr else { throw MIDIListenerError.clientCreationFailed(clientStatus) }
        self.client = client

        var port = MIDIPortRef()
        let portStatus = MIDIInputPortCreateWithBlock(client, "Input" as CFString, &port) { [weak self] packetListPointer, _ in
            self?.handle(packetListPointer)
        }
        guard portStatus == noErr else { throw MIDIListenerError.portCreationFailed(portStatus) }
        self.inputPort = port
    }

    /// Connects every source currently visible to CoreMIDI. Devices plugged in afterwards
    /// need a fresh call (no hot-plug notification handling yet).
    public func connectAllSources() {
        for index in 0..<MIDIGetNumberOfSources() {
            MIDIPortConnectSource(inputPort, MIDIGetSource(index), nil)
        }
    }

    /// Connects only the source at `index` in `sourceNames()`'s order — for when several
    /// sources are visible and only one of them should feed the app (e.g. a physical
    /// keyboard, ignoring an unrelated virtual IAC bus). Out-of-range indices are ignored
    /// rather than trapping, matching `connectAllSources()`'s no-throw shape.
    public func connectSource(atIndex index: Int) {
        guard (0..<MIDIGetNumberOfSources()).contains(index) else { return }
        MIDIPortConnectSource(inputPort, MIDIGetSource(index), nil)
    }

    public static func sourceNames() -> [String] {
        (0..<MIDIGetNumberOfSources()).map { index in
            let source = MIDIGetSource(index)
            var unmanagedName: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &unmanagedName)
            return (unmanagedName?.takeRetainedValue() as String?) ?? "Unknown source \(index)"
        }
    }

    private func handle(_ packetListPointer: UnsafePointer<MIDIPacketList>) {
        var packet = packetListPointer.pointee.packet
        withUnsafeMutablePointer(to: &packet) { firstPacket in
            var currentPacket = firstPacket
            for _ in 0..<packetListPointer.pointee.numPackets {
                let length = Int(currentPacket.pointee.length)
                let bytes = withUnsafeBytes(of: currentPacket.pointee.data) { rawBuffer in
                    Array(rawBuffer.prefix(length))
                }
                for event in MIDIRawParser.parseNoteEvents(bytes) {
                    handler(event)
                }
                currentPacket = MIDIPacketNext(currentPacket)
            }
        }
    }
}

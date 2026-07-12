import CoreMIDI

public enum MIDIListenerError: Error {
    case clientCreationFailed(OSStatus)
    case portCreationFailed(OSStatus)
}

/// One CoreMIDI source, as reported by `MIDIInputListener.sourceDescriptors()` — see that
/// function's own doc comment for why `uniqueID` (not this array's own index) is the identity
/// worth trusting across a reconnect.
public struct MIDISourceDescriptor: Sendable, Equatable {
    public let uniqueID: Int32?
    public let displayName: String
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
        sourceDescriptors().map(\.displayName)
    }

    /// Like `sourceNames()`, but also reads CoreMIDI's own persistent per-device identifier
    /// (`kMIDIPropertyUniqueID`) alongside the display name — unlike a source's position in
    /// this array (what `TrackID.midiSource(Int)` actually keys on), `uniqueID` is stable
    /// across unplug/replug of the SAME physical device on this Mac in the ordinary case, so
    /// it's what `AppCore.InstrumentIdentityHint.midiPort`/`ImprovSession.matches(_:_:)` use
    /// to recognize a previously-attached MIDI device automatically instead of just betting on
    /// "whatever's at the same index this time." Not a hardware guarantee (two identical
    /// models can still only be told apart by whichever id CoreMIDI happens to assign each
    /// instance, and some virtual/IAC ports may lack one) — `uniqueID` is `nil` for a source
    /// CoreMIDI doesn't report one for, in which case reattachment falls back to name-based
    /// matching (see that call site's own doc comment).
    public static func sourceDescriptors() -> [MIDISourceDescriptor] {
        (0..<MIDIGetNumberOfSources()).map { index in
            let source = MIDIGetSource(index)
            var unmanagedName: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &unmanagedName)
            let displayName = (unmanagedName?.takeRetainedValue() as String?) ?? "Unknown source \(index)"
            var uniqueID: Int32 = 0
            let status = MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &uniqueID)
            return MIDISourceDescriptor(uniqueID: status == noErr ? uniqueID : nil, displayName: displayName)
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

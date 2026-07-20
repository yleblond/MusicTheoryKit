import CoreMIDI

public enum MIDIOutputError: Error {
    case clientCreationFailed(OSStatus)
    case portCreationFailed(OSStatus)
    case destinationNotFound
    case sendFailed(OSStatus)
}

/// One CoreMIDI destination (a device's MIDI-IN), as reported by
/// `MIDIOutputPort.destinationDescriptors()` — the write-side counterpart to
/// `MIDISourceDescriptor`. A device that both sends and receives MIDI (like LUMI Keys, or
/// any class-compliant USB-MIDI keyboard) shows up as one entry here AND one separate entry
/// in `MIDIInputListener.sourceDescriptors()` — these are two different CoreMIDI
/// enumerations (`MIDIGetNumberOfDestinations`/`MIDIGetDestination` vs.
/// `MIDIGetNumberOfSources`/`MIDIGetSource`), not two views of the same list.
public struct MIDIDestinationDescriptor: Sendable, Equatable {
    public let uniqueID: Int32?
    public let displayName: String
}

/// Sends raw MIDI (including SysEx) to a chosen CoreMIDI destination. Deliberately the
/// mirror image of `MIDIInputListener`: that type only reads from sources, this type only
/// writes to destinations — a class-compliant device typically needs both, as two separate
/// CoreMIDI endpoints, to be fully driven (read its keys, write its lights).
public final class MIDIOutputPort {
    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()

    public init(clientName: String = "MusicImprovAssistant") throws {
        var client = MIDIClientRef()
        let clientStatus = MIDIClientCreateWithBlock(clientName as CFString, &client, nil)
        guard clientStatus == noErr else { throw MIDIOutputError.clientCreationFailed(clientStatus) }
        self.client = client

        var port = MIDIPortRef()
        let portStatus = MIDIOutputPortCreate(client, "Output" as CFString, &port)
        guard portStatus == noErr else { throw MIDIOutputError.portCreationFailed(portStatus) }
        self.outputPort = port
    }

    /// The index into `destinationDescriptors()` of the single destination whose display
    /// name contains `substring` (case-insensitive) — `nil` if none match or if more than
    /// one does (ambiguous, caller should ask rather than guess). Factored out of
    /// `LumiSpike`'s own identical logic so callers that also want "just find the LUMI"
    /// (e.g. `ImprovSession`) don't re-implement it.
    public static func autoDetectedDestinationIndex(nameContains substring: String) -> Int? {
        let matches = destinationDescriptors().enumerated().filter {
            $0.element.displayName.localizedCaseInsensitiveContains(substring)
        }
        guard matches.count == 1 else { return nil }
        return matches.first?.offset
    }

    /// Like `MIDIInputListener.sourceDescriptors()`, but for destinations — see that
    /// function's own doc comment for why `uniqueID` (not this array's index) is what's
    /// worth persisting across a reconnect.
    public static func destinationDescriptors() -> [MIDIDestinationDescriptor] {
        (0..<MIDIGetNumberOfDestinations()).map { index in
            let destination = MIDIGetDestination(index)
            var unmanagedName: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(destination, kMIDIPropertyDisplayName, &unmanagedName)
            let displayName = (unmanagedName?.takeRetainedValue() as String?) ?? "Unknown destination \(index)"
            var uniqueID: Int32 = 0
            let status = MIDIObjectGetIntegerProperty(destination, kMIDIPropertyUniqueID, &uniqueID)
            return MIDIDestinationDescriptor(uniqueID: status == noErr ? uniqueID : nil, displayName: displayName)
        }
    }

    /// Sends `bytes` (e.g. a full `F0 ... F7` SysEx message) as a single MIDI packet to the
    /// destination at `index` in `destinationDescriptors()`'s order.
    ///
    /// Uses `MIDIPacketListInit`/`MIDIPacketListAdd`/`MIDISend` rather than the older
    /// `MIDISendSysex`/`MIDISysexSendRequest` pair: that API's request struct must stay
    /// alive for the whole asynchronous, possibly paced/chunked send — a real lifetime
    /// hazard for a struct that's easy to let go out of scope mid-send. It exists to pace
    /// large SysEx dumps; LUMI's messages here are ~16 bytes, far below anything needing
    /// that, so a single synchronous packet list is both simpler and has no such hazard.
    /// `MIDIPacketList` is itself a variable-length C struct (its `packet` field is really
    /// the first of a run of packets packed back-to-back in memory) — allocating it on the
    /// heap with generous headroom, not as a bare stack `var`, is what makes writing a
    /// multi-byte packet into it via `MIDIPacketListAdd` safe.
    public func send(_ bytes: [UInt8], toDestinationAtIndex index: Int) throws {
        guard (0..<MIDIGetNumberOfDestinations()).contains(index) else { throw MIDIOutputError.destinationNotFound }
        try send(bytes, to: MIDIGetDestination(index))
    }

    public func send(_ bytes: [UInt8], to destination: MIDIEndpointRef) throws {
        // This SDK imports MIDIPacketListAdd's return as non-optional, so there's no nil
        // to check for "didn't fit" — bufferSize is generous enough (LUMI messages are
        // ~16 bytes) that it never comes close to the one real constraint that matters:
        // a MIDIPacketList's data capacity, which callers must size themselves.
        let bufferSize = 1024
        let listPointer = UnsafeMutablePointer<MIDIPacketList>.allocate(capacity: 1)
        defer { listPointer.deallocate() }

        let firstPacket = MIDIPacketListInit(listPointer)
        _ = MIDIPacketListAdd(listPointer, bufferSize, firstPacket, 0, bytes.count, bytes)

        let status = MIDISend(outputPort, destination, listPointer)
        guard status == noErr else { throw MIDIOutputError.sendFailed(status) }
    }
}

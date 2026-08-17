import Foundation

/// Reads a Standard MIDI File (SMF, `.mid`/`.midi`) into a `RawScore`. Hand-rolled — SMF's
/// chunk/VLQ/event structure is simple and well documented, no third-party dependency needed.
///
/// Distinct from `MIDIEngine`'s `MIDIRawParser`: that one decodes a live, delta-time-free byte
/// stream from CoreMIDI; this reads delta-time-prefixed track chunks from a file. The one piece
/// of logic shared between them is the **running status** rule for channel-voice messages
/// (a repeated status byte omitted for consecutive same-channel messages) — reapplied here
/// against SMF's own container, not imported from `MIDIEngine` (this target has no CoreMIDI
/// dependency and shouldn't gain one just to reuse a ~10-line rule).
public enum SMFReader {
    public enum SMFError: Error, Equatable {
        case invalidHeader
        /// SMPTE-frame-based division (top bit of MThd's division field set) — rare for
        /// single-piece exports, not supported in v1.
        case unsupportedDivision
        /// Format 2 (independent, unsynchronized sequences) — not a single piece's timeline,
        /// not supported in v1.
        case unsupportedFormat(Int)
        case truncatedData
    }

    public static func parse(contentsOf url: URL) throws -> RawScore {
        try parse(data: Data(contentsOf: url))
    }

    public static func parse(data: Data) throws -> RawScore {
        var cursor = ByteCursor(data: data)

        guard try cursor.readChunkID() == "MThd" else { throw SMFError.invalidHeader }
        let headerLength = Int(try cursor.readUInt32BE())
        guard headerLength >= 6 else { throw SMFError.invalidHeader }
        let format = Int(try cursor.readUInt16BE())
        let trackCount = Int(try cursor.readUInt16BE())
        let division = try cursor.readUInt16BE()
        if headerLength > 6 { try cursor.skip(headerLength - 6) }

        guard division & 0x8000 == 0 else { throw SMFError.unsupportedDivision }
        guard format == 0 || format == 1 else { throw SMFError.unsupportedFormat(format) }
        let ticksPerQuarterNote = Int(division)

        var tempoMap: [RawTempoEvent] = []
        var timeSignatureMap: [RawTimeSignatureEvent] = []
        var keySignatureMap: [RawKeySignatureEvent] = []
        var trackResults: [TrackParseResult] = []

        for _ in 0..<trackCount {
            guard try cursor.readChunkID() == "MTrk" else { throw SMFError.invalidHeader }
            let trackLength = Int(try cursor.readUInt32BE())
            let trackEnd = cursor.offset + trackLength
            let track = try parseTrack(cursor: &cursor, end: trackEnd)
            tempoMap.append(contentsOf: track.tempoEvents)
            timeSignatureMap.append(contentsOf: track.timeSigEvents)
            keySignatureMap.append(contentsOf: track.keySigEvents)
            trackResults.append(track)
            cursor.seek(to: trackEnd) // defensive resync in case a track's own events didn't add up exactly
        }

        let parts: [RawPart]
        if format == 0 {
            // A single track carrying every channel interleaved — the only per-instrument
            // grouping available is MIDI channel.
            parts = splitByChannel(trackResults.flatMap(\.notes))
        } else {
            parts = trackResults.enumerated().compactMap { index, track -> RawPart? in
                guard !track.notes.isEmpty else { return nil } // e.g. a tempo-only track
                let notes = track.notes
                    .sorted { $0.startTick < $1.startTick }
                    .map { RawNote(startTick: $0.startTick, durationTicks: $0.durationTicks, pitch: $0.pitch, velocity: $0.velocity) }
                return RawPart(
                    id: String(index), name: track.name ?? "Track \(index + 1)",
                    instrumentHint: track.programNames.values.first, notes: notes
                )
            }
        }

        return RawScore(
            sourceFormat: .midi,
            title: trackResults.first?.name,
            divisionsPerQuarterNote: ticksPerQuarterNote,
            tempoMap: tempoMap.sorted { $0.tick < $1.tick },
            timeSignatureMap: timeSignatureMap.sorted { $0.tick < $1.tick },
            keySignatureMap: keySignatureMap.sorted { $0.tick < $1.tick },
            parts: parts
        )
    }

    // MARK: - Track parsing

    private struct MIDIParsedNote {
        var channel: Int
        var startTick: Int
        var durationTicks: Int
        var pitch: Int
        var velocity: Int
    }

    private struct TrackParseResult {
        var name: String?
        var notes: [MIDIParsedNote] = []
        var tempoEvents: [RawTempoEvent] = []
        var timeSigEvents: [RawTimeSignatureEvent] = []
        var keySigEvents: [RawKeySignatureEvent] = []
        var programNames: [Int: String] = [:] // channel -> last GM program name seen
    }

    private static func parseTrack(cursor: inout ByteCursor, end: Int) throws -> TrackParseResult {
        var result = TrackParseResult(name: nil)
        var absoluteTick = 0
        var runningStatus: UInt8?
        // FIFO per (channel, pitch) so overlapping same-pitch note-ons (legal, if rare) pair
        // with note-offs in the order they were opened, rather than corrupting an unrelated note.
        var openNotes: [Int: [(startTick: Int, velocity: Int)]] = [:]

        while cursor.offset < end {
            absoluteTick += try cursor.readVLQ()
            let peeked = try cursor.peekByte()

            if peeked == 0xFF {
                _ = try cursor.readByte()
                let metaType = try cursor.readByte()
                let length = try cursor.readVLQ()
                let data = try cursor.readBytes(length)
                runningStatus = nil
                applyMetaEvent(type: metaType, data: data, tick: absoluteTick, into: &result)
                continue
            }
            if peeked == 0xF0 || peeked == 0xF7 {
                _ = try cursor.readByte()
                let length = try cursor.readVLQ()
                try cursor.skip(length)
                runningStatus = nil
                continue
            }

            let status: UInt8
            if peeked & 0x80 != 0 {
                status = try cursor.readByte()
            } else if let running = runningStatus {
                status = running // peeked byte is the first data byte of this running-status message, left unconsumed
            } else {
                _ = try cursor.readByte() // stray data byte with no status context — skip defensively
                continue
            }
            runningStatus = status
            let messageType = status & 0xF0
            let channel = Int(status & 0x0F)

            switch messageType {
            case 0x80, 0x90: // note off / note on
                let data = try cursor.readBytes(2)
                let pitch = Int(data[0])
                let velocity = Int(data[1])
                let key = channel * 128 + pitch
                if messageType == 0x90 && velocity > 0 {
                    openNotes[key, default: []].append((startTick: absoluteTick, velocity: velocity))
                } else if var stack = openNotes[key], !stack.isEmpty {
                    // Duration/pitch come from this closing event, but velocity must come from
                    // the note-ON that opened it — a note-off's own data byte is a release
                    // velocity (usually 0 or ignored), not the note's sounding velocity.
                    let opened = stack.removeFirst()
                    openNotes[key] = stack
                    result.notes.append(MIDIParsedNote(
                        channel: channel, startTick: opened.startTick,
                        durationTicks: max(absoluteTick - opened.startTick, 1), pitch: pitch, velocity: opened.velocity
                    ))
                }
            case 0xA0, 0xB0, 0xE0: // poly aftertouch, control change, pitch bend — 2 data bytes
                _ = try cursor.readBytes(2)
            case 0xC0: // program change — 1 data byte
                let data = try cursor.readBytes(1)
                result.programNames[channel] = generalMIDIProgramNames[safe: Int(data[0])]
            case 0xD0: // channel aftertouch — 1 data byte
                _ = try cursor.readBytes(1)
            default:
                // An unrecognized/unsupported status (shouldn't occur for 0x8n...0xEn) — drop
                // running status so the next iteration resyncs on the next real status byte.
                runningStatus = nil
            }
        }
        return result
    }

    private static func applyMetaEvent(type: UInt8, data: [UInt8], tick: Int, into result: inout TrackParseResult) {
        switch type {
        case 0x03: // sequence/track name
            result.name = String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .ascii)
        case 0x51: // set tempo — 3-byte microseconds per quarter note
            guard data.count == 3 else { return }
            let mpq = Int(data[0]) << 16 | Int(data[1]) << 8 | Int(data[2])
            result.tempoEvents.append(RawTempoEvent(tick: tick, microsecondsPerQuarter: mpq))
        case 0x58: // time signature — numerator, log2(denominator), clocks/click, 32nds/quarter
            guard data.count >= 2 else { return }
            let beatsPerMeasure = Int(data[0])
            let beatUnit = 1 << Int(data[1])
            result.timeSigEvents.append(RawTimeSignatureEvent(tick: tick, beatsPerMeasure: beatsPerMeasure, beatUnit: beatUnit))
        case 0x59: // key signature — signed sharps/flats count, major/minor flag
            guard data.count >= 2 else { return }
            let fifths = Int(Int8(bitPattern: data[0]))
            let isMinor = data[1] != 0
            result.keySigEvents.append(RawKeySignatureEvent(tick: tick, fifths: fifths, isMinor: isMinor))
        default:
            break // end-of-track (0x2F) and everything else: no RawScore field to populate
        }
    }

    private static func splitByChannel(_ notes: [MIDIParsedNote]) -> [RawPart] {
        let channels = Set(notes.map(\.channel)).sorted()
        return channels.map { channel in
            let channelNotes = notes
                .filter { $0.channel == channel }
                .sorted { $0.startTick < $1.startTick }
                .map { RawNote(startTick: $0.startTick, durationTicks: $0.durationTicks, pitch: $0.pitch, velocity: $0.velocity) }
            return RawPart(id: String(channel), name: "Channel \(channel + 1)", notes: channelNotes)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// A byte-offset cursor over an in-memory SMF, with the primitives SMF parsing needs
/// (big-endian fixed-width reads, 4-char chunk IDs, variable-length quantities).
private struct ByteCursor {
    let bytes: [UInt8]
    var offset: Int = 0

    init(data: Data) { bytes = [UInt8](data) }

    func peekByte() throws -> UInt8 {
        guard offset < bytes.count else { throw SMFReader.SMFError.truncatedData }
        return bytes[offset]
    }

    mutating func readByte() throws -> UInt8 {
        let byte = try peekByte()
        offset += 1
        return byte
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= bytes.count else { throw SMFReader.SMFError.truncatedData }
        defer { offset += count }
        return Array(bytes[offset ..< offset + count])
    }

    mutating func readUInt16BE() throws -> UInt16 {
        let b = try readBytes(2)
        return UInt16(b[0]) << 8 | UInt16(b[1])
    }

    mutating func readUInt32BE() throws -> UInt32 {
        let b = try readBytes(4)
        return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
    }

    mutating func readChunkID() throws -> String {
        let b = try readBytes(4)
        return String(bytes: b, encoding: .ascii) ?? ""
    }

    /// MIDI variable-length quantity: each byte's top bit is a continuation flag, 7 data bits
    /// each, most-significant group first.
    mutating func readVLQ() throws -> Int {
        var value = 0
        while true {
            let byte = try readByte()
            value = (value << 7) | Int(byte & 0x7F)
            if byte & 0x80 == 0 { break }
        }
        return value
    }

    mutating func skip(_ count: Int) throws {
        guard count >= 0, offset + count <= bytes.count else { throw SMFReader.SMFError.truncatedData }
        offset += count
    }

    mutating func seek(to newOffset: Int) {
        offset = min(max(newOffset, 0), bytes.count)
    }
}

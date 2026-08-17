import Foundation

/// Reads MusicXML (`.musicxml`/`.xml`, or `.mxl` — MusicXML's own compressed ZIP container) into
/// a `RawScore`. Hand-rolled on top of Foundation's built-in `XMLParser` (no third-party
/// dependency needed, same style as `SMFReader`); `.mxl` decompression reuses `ZipArchiveReader`
/// as-is.
///
/// v1 scope: `<score-partwise>` only (`<score-timewise>` — the same music organized measure-first
/// instead of part-first — is legal MusicXML but rare for real exports and rejected explicitly
/// rather than silently mis-parsed, same spirit as `SMFReader`'s format-2 rejection). Within a
/// part: pitch/rest/duration/chord/tie/voice/staff, `<attributes>` (divisions/key/time),
/// `<backup>`/`<forward>`, `<harmony>` chord symbols, `<sound tempo>`, and plain
/// `<repeat direction="forward"/>`/`<repeat direction="backward" times="N"/>` barlines (expanded
/// into the final tick timeline — see `expandedMeasureOrder(measureCount:markers:)`). NOT in v1
/// scope: grace notes (skipped — no duration to place them at), multi-movement files, anything
/// requiring `<time-modification>` (irrelevant here: MusicXML's `<duration>` already reflects
/// real, tuplet-adjusted time regardless of the tuplet's display bracket), and first/second
/// endings (`<ending>`/volta) — a repeat with different endings will incorrectly include the
/// ending measure(s) in every pass rather than being handled correctly.
public enum MusicXMLReader {
    public enum MusicXMLError: Error, Equatable {
        case notMusicXML
        case unsupportedDocumentType(String)
        case missingRootfile
        case xmlParseFailed(String)
    }

    private static let outputDivisionsPerQuarter = 480

    /// One `<repeat>` barline as encountered, from whichever part is `partOrder.first` (every
    /// part in a valid score declares the same barline structure redundantly; only the first is
    /// read, to avoid double-counting).
    private enum RepeatDirection { case forward, backward }
    private struct RepeatMarker { let measureIndex: Int; let direction: RepeatDirection; let times: Int? }

    /// Expands `forward`/`backward` repeat barlines into the actual measure PLAY order (e.g.
    /// `[0, 1, 2, 1, 2, 3]` for a repeat spanning measures 1-2) — measure indices are 0-based,
    /// local to one part, and assumed identical in count/order across every part of a valid
    /// score, so the SAME order applies uniformly to each part's own bucketed measures. A
    /// `backward` with no preceding `forward` repeats from the start of the piece (measure 0),
    /// the usual notation convention; `times` (total play count, not repeat count) defaults to 2
    /// when the source doesn't specify it. `safetyLimit` bounds the loop defensively against a
    /// malformed file with contradictory markers, degrading to a truncated expansion rather than
    /// hanging.
    private static func expandedMeasureOrder(measureCount: Int, markers: [RepeatMarker]) -> [Int] {
        guard measureCount > 0 else { return [] }
        guard !markers.isEmpty else { return Array(0..<measureCount) }

        var backwardInfo: [Int: (times: Int, startIndex: Int)] = [:]
        var lastForwardIndex = 0
        for marker in markers.sorted(by: { $0.measureIndex < $1.measureIndex }) {
            switch marker.direction {
            case .forward: lastForwardIndex = marker.measureIndex
            case .backward: backwardInfo[marker.measureIndex] = (times: marker.times ?? 2, startIndex: lastForwardIndex)
            }
        }

        var order: [Int] = []
        var playCounts: [Int: Int] = [:]
        var i = 0
        var safetyLimit = measureCount * 8 + 16
        while i < measureCount, safetyLimit > 0 {
            safetyLimit -= 1
            order.append(i)
            if let info = backwardInfo[i] {
                let played = playCounts[i, default: 1]
                if played < info.times {
                    playCounts[i] = played + 1
                    i = info.startIndex
                    continue
                }
            }
            i += 1
        }
        return order
    }

    public static func parse(contentsOf url: URL) throws -> RawScore {
        try parse(data: Data(contentsOf: url))
    }

    public static func parse(data: Data) throws -> RawScore {
        let xmlData = try isZipArchive(data) ? extractMusicXML(fromCompressed: data) : data
        let delegate = PartwiseParserDelegate()
        let parser = XMLParser(data: xmlData)
        parser.delegate = delegate
        guard parser.parse() else {
            if let error = delegate.parseError { throw error }
            throw MusicXMLError.xmlParseFailed(parser.parserError?.localizedDescription ?? "unknown")
        }
        if let error = delegate.parseError { throw error }
        return delegate.makeRawScore(outputDivisionsPerQuarter: outputDivisionsPerQuarter)
    }

    // MARK: - Compressed (.mxl) handling

    private static func isZipArchive(_ data: Data) -> Bool {
        data.count >= 4 && data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4B
            && data[data.startIndex + 2] == 0x03 && data[data.startIndex + 3] == 0x04
    }

    /// The MusicXML compressed-format spec requires an indirection through
    /// `META-INF/container.xml` rather than assuming the "obvious" `.xml`/`.musicxml`-looking
    /// entry is the score — a compliant `.mxl` can bundle other files (e.g. an audio preview)
    /// alongside it.
    private static func extractMusicXML(fromCompressed data: Data) throws -> Data {
        let containerXML = try ZipArchiveReader.extract(entryName: "META-INF/container.xml", from: data)
        guard let containerText = String(data: containerXML, encoding: .utf8),
              let match = containerText.range(of: #"full-path="([^"]+)""#, options: .regularExpression) else {
            throw MusicXMLError.missingRootfile
        }
        let rootPath = String(containerText[match])
            .replacingOccurrences(of: "full-path=\"", with: "")
            .replacingOccurrences(of: "\"", with: "")
        return try ZipArchiveReader.extract(entryName: rootPath, from: data)
    }

    // MARK: - SAX delegate

    private final class PartwiseParserDelegate: NSObject, XMLParserDelegate {
        var parseError: Error?

        private var title: String?
        private var composer: String?
        private var partOrder: [String] = []
        private var partNames: [String: String] = [:]
        /// Notes bucketed by measure (not a flat per-part list) so repeats can be expanded
        /// afterward — see `makeRawScore(outputDivisionsPerQuarter:)`. Ticks inside a bucket are
        /// still absolute, computed exactly as before; only the grouping is new.
        private var measuresByPart: [String: [MeasureBucket]] = [:]
        private struct MeasureBucket { var startTick: Int; var endTick: Int; var notes: [RawNote] = [] }
        private var repeatMarkers: [RepeatMarker] = []
        private var tempoMap: [RawTempoEvent] = []
        private var timeSignatureMap: [RawTimeSignatureEvent] = []
        private var keySignatureMap: [RawKeySignatureEvent] = []
        private var explicitChords: [RawChordSymbol] = []

        private var elementStack: [String] = []
        private var text = ""

        // Reset per `<part>`.
        private var currentPartID: String?
        private var currentPartDivisions = 1
        private var cursorTick = 0
        private var previousNoteStartTick = 0
        private var currentMeasureIndex = -1

        // Reset per `<identification><creator>`.
        private var creatorType: String?

        // Reset per `<score-part>`.
        private var currentScorePartID: String?

        // Reset per `<note>`.
        private var inGraceNote = false
        private var noteIsRest = false
        private var noteIsChord = false
        private var notePitchStep: String?
        private var notePitchAlter = 0
        private var notePitchOctave = 4
        private var noteDuration = 0
        private var noteVoice: Int?
        private var noteStaff: Int?
        private var noteTieStart = false
        private var noteTieStop = false

        // Reset per `<harmony>`.
        private var inHarmony = false
        private var harmonyRootStep: String?
        private var harmonyRootAlter = 0
        private var harmonyKind: String?

        func makeRawScore(outputDivisionsPerQuarter: Int) -> RawScore {
            let measureCount = measuresByPart[partOrder.first ?? ""]?.count ?? 0
            let order = MusicXMLReader.expandedMeasureOrder(measureCount: measureCount, markers: repeatMarkers)
            let parts = partOrder.map { id -> RawPart in
                let buckets = measuresByPart[id] ?? []
                var notes: [RawNote] = []
                var expansionCursor = 0
                for measureIndex in order where buckets.indices.contains(measureIndex) {
                    let bucket = buckets[measureIndex]
                    let offset = expansionCursor - bucket.startTick
                    for var note in bucket.notes {
                        note.startTick += offset
                        notes.append(note)
                    }
                    expansionCursor += bucket.endTick - bucket.startTick
                }
                return RawPart(id: id, name: partNames[id], notes: notes.sorted { $0.startTick < $1.startTick })
            }
            return RawScore(
                sourceFormat: .musicXML, title: title, composer: composer,
                divisionsPerQuarterNote: outputDivisionsPerQuarter,
                tempoMap: tempoMap.sorted { $0.tick < $1.tick },
                timeSignatureMap: timeSignatureMap.sorted { $0.tick < $1.tick },
                keySignatureMap: keySignatureMap.sorted { $0.tick < $1.tick },
                parts: parts, explicitChords: explicitChords.sorted { $0.tick < $1.tick }
            )
        }

        private func rescaledTicks(_ divisionsValue: Int) -> Int {
            guard currentPartDivisions > 0 else { return divisionsValue }
            return Int((Double(divisionsValue) * Double(outputDivisionsPerQuarter) / Double(currentPartDivisions)).rounded())
        }

        // MARK: XMLParserDelegate

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if elementStack.isEmpty, elementName != "score-partwise" {
                parseError = MusicXMLReader.MusicXMLError.unsupportedDocumentType(elementName)
                parser.abortParsing()
                return
            }
            elementStack.append(elementName)
            text = ""

            switch elementName {
            case "score-part":
                currentScorePartID = attributeDict["id"]
                if let id = currentScorePartID { partOrder.append(id) }
            case "part":
                currentPartID = attributeDict["id"]
                currentPartDivisions = 1
                cursorTick = 0
                previousNoteStartTick = 0
                currentMeasureIndex = -1
            case "measure":
                currentMeasureIndex += 1
                if let currentPartID {
                    measuresByPart[currentPartID, default: []].append(MeasureBucket(startTick: cursorTick, endTick: cursorTick))
                }
            case "repeat":
                if currentPartID == partOrder.first, let direction = attributeDict["direction"] {
                    let repeatDirection: RepeatDirection? = direction == "forward" ? .forward : (direction == "backward" ? .backward : nil)
                    if let repeatDirection {
                        repeatMarkers.append(RepeatMarker(measureIndex: currentMeasureIndex, direction: repeatDirection, times: attributeDict["times"].flatMap(Int.init)))
                    }
                }
            case "creator":
                creatorType = attributeDict["type"]
            case "note":
                inGraceNote = false
                noteIsRest = false
                noteIsChord = false
                notePitchStep = nil
                notePitchAlter = 0
                notePitchOctave = 4
                noteDuration = 0
                noteVoice = nil
                noteStaff = nil
                noteTieStart = false
                noteTieStop = false
            case "grace":
                inGraceNote = true
            case "rest":
                noteIsRest = true
            case "chord":
                noteIsChord = true
            case "tie":
                if attributeDict["type"] == "start" { noteTieStart = true }
                if attributeDict["type"] == "stop" { noteTieStop = true }
            case "harmony":
                inHarmony = true
                harmonyRootStep = nil
                harmonyRootAlter = 0
                harmonyKind = nil
            case "sound":
                if let tempoText = attributeDict["tempo"], let tempo = Double(tempoText), tempo > 0 {
                    tempoMap.append(RawTempoEvent(tick: cursorTick, microsecondsPerQuarter: Int((60_000_000 / tempo).rounded())))
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            defer {
                elementStack.removeLast()
                text = ""
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            switch elementName {
            case "work-title":
                if elementStack.dropLast().last == "work" { title = trimmed }
            case "creator":
                if creatorType == "composer" { composer = trimmed }
            case "part-name":
                if elementStack.dropLast().last == "score-part", let id = currentScorePartID {
                    partNames[id] = trimmed
                }
            case "divisions":
                if let value = Int(trimmed) { currentPartDivisions = max(value, 1) }
            case "fifths":
                if elementStack.dropLast().last == "key" {
                    keySignatureMap.append(RawKeySignatureEvent(tick: cursorTick, fifths: Int(trimmed) ?? 0))
                }
            case "mode":
                if elementStack.dropLast().last == "key", let last = keySignatureMap.last, last.tick == cursorTick {
                    keySignatureMap[keySignatureMap.count - 1] = RawKeySignatureEvent(tick: cursorTick, fifths: last.fifths, isMinor: trimmed == "minor")
                }
            case "beats":
                if elementStack.dropLast().last == "time" { pendingTimeBeats = Int(trimmed) }
            case "beat-type":
                if elementStack.dropLast().last == "time", let beats = pendingTimeBeats, let beatType = Int(trimmed) {
                    timeSignatureMap.append(RawTimeSignatureEvent(tick: cursorTick, beatsPerMeasure: beats, beatUnit: beatType))
                    pendingTimeBeats = nil
                }
            case "step":
                if elementStack.dropLast().last == "pitch" { notePitchStep = trimmed }
            case "root-step":
                if inHarmony { harmonyRootStep = trimmed }
            case "root-alter":
                if inHarmony { harmonyRootAlter = Int(trimmed) ?? 0 }
            case "alter":
                if elementStack.dropLast().last == "pitch" { notePitchAlter = Int(trimmed) ?? 0 }
            case "octave":
                if elementStack.dropLast().last == "pitch" { notePitchOctave = Int(trimmed) ?? 4 }
            case "kind":
                if inHarmony { harmonyKind = trimmed }
            case "duration":
                // Shared by <note>, <backup>, and <forward> — disambiguate by the enclosing element.
                let raw = Int(trimmed) ?? 0
                switch elementStack.dropLast().last {
                case "note": noteDuration = raw
                case "backup": cursorTick -= rescaledTicks(raw)
                case "forward": cursorTick += rescaledTicks(raw)
                default: break
                }
            case "voice":
                if elementStack.dropLast().last == "note" { noteVoice = Int(trimmed) }
            case "staff":
                if elementStack.dropLast().last == "note" { noteStaff = Int(trimmed) }
            case "harmony":
                inHarmony = false
                if let step = harmonyRootStep {
                    explicitChords.append(RawChordSymbol(tick: cursorTick, rootStep: step, rootAlter: harmonyRootAlter, kind: harmonyKind ?? "major"))
                }
            case "note":
                guard !inGraceNote else { break } // no duration to place a grace note at meaningfully — skipped, not approximated
                let durationTicks = max(rescaledTicks(noteDuration), 1)
                let startTick = noteIsChord ? previousNoteStartTick : cursorTick
                let pitch: Int
                var spelling: RawSpelling?
                if noteIsRest {
                    pitch = 0
                } else if let step = notePitchStep {
                    let stepSemitones: [String: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
                    pitch = (notePitchOctave + 1) * 12 + (stepSemitones[step] ?? 0) + notePitchAlter
                    spelling = RawSpelling(step: step, alter: notePitchAlter, octave: notePitchOctave)
                } else {
                    pitch = 0
                }
                if let currentPartID, measuresByPart[currentPartID]?.isEmpty == false {
                    measuresByPart[currentPartID]![measuresByPart[currentPartID]!.count - 1].notes.append(RawNote(
                        startTick: startTick, durationTicks: durationTicks, pitch: pitch,
                        spelling: spelling, isRest: noteIsRest, voice: noteVoice, staff: noteStaff,
                        tieStart: noteTieStart, tieStop: noteTieStop
                    ))
                }
                if !noteIsChord {
                    previousNoteStartTick = cursorTick
                    cursorTick += durationTicks
                }
            case "measure":
                if let currentPartID, measuresByPart[currentPartID]?.isEmpty == false {
                    measuresByPart[currentPartID]![measuresByPart[currentPartID]!.count - 1].endTick = cursorTick
                }
            default:
                break
            }
        }

        // `<time><beats>4</beats><beat-type>4</beat-type></time>` needs both children before a
        // `RawTimeSignatureEvent` can be built.
        private var pendingTimeBeats: Int?

        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
            // Ignore a trailing/spurious error after we already aborted intentionally above.
            if self.parseError == nil { self.parseError = MusicXMLReader.MusicXMLError.xmlParseFailed(parseError.localizedDescription) }
        }
    }
}

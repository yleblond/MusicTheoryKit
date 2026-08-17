import Foundation

/// Reads MuseScore's own native format (`.mscz` — a ZIP container around one top-level `.mscx`
/// XML file, MuseScore's own convention — or a loose `.mscx` file directly) into a `RawScore`.
/// Hand-rolled on Foundation's `XMLParser`, same style as `MusicXMLReader`; `.mscz` decompression
/// reuses `ZipArchiveReader` as-is.
///
/// Unlike MusicXML, MuseScore's `.mscx` schema is MuseScore's own internal format, not a
/// documented public standard, and its element shapes have changed across major versions (2/3/4
/// each differ). This targets the current MuseScore 4.x schema; a `<museScore version="...">`
/// whose major version isn't 4 throws `unsupportedSchemaVersion` rather than attempting a
/// best-effort parse against the wrong shape, which could silently produce wrong music.
///
/// Schema notes (MuseScore-specific, unlike MusicXML): a `<Chord>` groups 1+ simultaneous
/// `<Note>`s under one shared `<durationType>` (a name — "quarter", "eighth", etc. — not a raw
/// division count); `<Note><pitch>` is already an absolute MIDI number; `<tpc>` ("tonal pitch
/// class") is MuseScore's own circle-of-fifths pitch-spelling encoding, decoded below into
/// `RawSpelling` via the standard `step = (tpc+1) mod 7` / `alter = floorDiv(tpc+1, 7) - 2`
/// formula (`F C G D A E B` in TPC order starting at 13); `<Tempo><tempo>` is quarter notes per
/// SECOND (not per minute, unlike MusicXML's `<sound tempo>`).
public enum MuseScoreReader {
    public enum MuseScoreError: Error, Equatable {
        case notMuseScore
        case unsupportedSchemaVersion(String)
        case missingScoreEntry
        case xmlParseFailed(String)
    }

    private static let outputDivisionsPerQuarter = 480

    /// See `MusicXMLReader`'s identical-in-spirit `RepeatMarker`/`expandedMeasureOrder` — same
    /// v1 scope (plain repeats, no first/second endings), same algorithm, applied to MuseScore's
    /// own `<startRepeat/>` (a bare marker) / `<endRepeat>N</endRepeat>` (N = total play count)
    /// instead of MusicXML's `<repeat direction="..." times="...">`. Verified against a real
    /// 2.06 file: both markers are declared once, in the first staff only (not redundantly
    /// per-staff like MusicXML's barlines) — matching the "only `staffOrder.first`" capture rule
    /// below regardless of which convention a given file actually follows.
    private enum RepeatDirection { case forward, backward }
    private struct RepeatMarker { let measureIndex: Int; let direction: RepeatDirection; let times: Int? }

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
        let xmlData = try isZipArchive(data) ? extractMscx(fromCompressed: data) : data
        let delegate = MuseScoreParserDelegate()
        let parser = XMLParser(data: xmlData)
        parser.delegate = delegate
        guard parser.parse() else {
            if let error = delegate.parseError { throw error }
            throw MuseScoreError.xmlParseFailed(parser.parserError?.localizedDescription ?? "unknown")
        }
        if let error = delegate.parseError { throw error }
        return delegate.makeRawScore(outputDivisionsPerQuarter: outputDivisionsPerQuarter)
    }

    // MARK: - Compressed (.mscz) handling

    private static func isZipArchive(_ data: Data) -> Bool {
        data.count >= 4 && data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4B
            && data[data.startIndex + 2] == 0x03 && data[data.startIndex + 3] == 0x04
    }

    /// MuseScore's own convention (unlike MusicXML's `.mxl`, there is no `META-INF/container.xml`
    /// indirection here): exactly one top-level `.mscx` entry, named after the score.
    private static func extractMscx(fromCompressed data: Data) throws -> Data {
        guard let name = try ZipArchiveReader.listEntryNames(data: data).first(where: { $0.hasSuffix(".mscx") }) else {
            throw MuseScoreError.missingScoreEntry
        }
        return try ZipArchiveReader.extract(entryName: name, from: data)
    }

    // MARK: - Duration

    /// `<durationType>` names to a fraction of a whole note — `<dots>N</dots>` (handled by the
    /// caller) adds the usual `1 + 1/2 + 1/4 + ...` for N dots on top.
    private static let durationTypeFractions: [String: Double] = [
        "whole": 1, "half": 0.5, "quarter": 0.25, "eighth": 0.125,
        "16th": 0.0625, "32nd": 0.03125, "64th": 0.015625, "128th": 0.0078125,
        "measure": 1, // a full-measure rest — treated as one whole note's worth, a v1 approximation for unusual time signatures
    ]

    private static func ticks(durationType: String, dots: Int, overrideFraction: Double? = nil) -> Int {
        let fraction: Double
        if let overrideFraction {
            fraction = overrideFraction
        } else {
            let base = durationTypeFractions[durationType] ?? 0.25
            var f = base
            var addend = base
            for _ in 0..<dots { addend /= 2; f += addend }
            fraction = f
        }
        return max(Int((fraction * 4 * Double(outputDivisionsPerQuarter)).rounded()), 1)
    }

    /// MuseScore's TPC ("tonal pitch class") is a circle-of-fifths integer — 13...19 are the
    /// seven natural letter names starting at F, each successive group of 7 above/below shifts
    /// the accidental by one sharp/flat. `octave` is recovered from the absolute `pitch` itself
    /// (MIDI already encodes it), not from the TPC.
    private static func spelling(pitch: Int, tpc: Int) -> RawSpelling {
        let steps = ["F", "C", "G", "D", "A", "E", "B"]
        let shifted = tpc + 1
        let stepIndex = ((shifted % 7) + 7) % 7
        let alter = Int(floor(Double(shifted) / 7.0)) - 2
        return RawSpelling(step: steps[stepIndex], alter: alter, octave: pitch / 12 - 1)
    }

    // MARK: - SAX delegate

    private final class MuseScoreParserDelegate: NSObject, XMLParserDelegate {
        var parseError: Error?

        private var title: String?
        private var composer: String?
        private var trackNameByStaffID: [String: String] = [:]
        private var staffOrder: [String] = []
        /// Notes bucketed by measure (not a flat per-staff list) so repeats can be expanded
        /// afterward — see `makeRawScore(outputDivisionsPerQuarter:)`.
        private var measuresByStaff: [String: [MeasureBucket]] = [:]
        private struct MeasureBucket { var startTick: Int; var endTick: Int; var notes: [RawNote] = [] }
        private var repeatMarkers: [RepeatMarker] = []
        private var currentMeasureIndex = -1
        private var tempoMap: [RawTempoEvent] = []
        private var timeSignatureMap: [RawTimeSignatureEvent] = []
        private var keySignatureMap: [RawKeySignatureEvent] = []
        private var explicitChords: [RawChordSymbol] = []

        private var elementStack: [String] = []
        private var text = ""

        // `<Part><Staff id="N"/><Staff id="M"/>...<trackName>...</trackName></Part>` — a `<Part>`
        // spanning a grand staff (e.g. piano) declares ONE shared `<trackName>` for ALL of its
        // `<Staff>` children, not one each — every id seen while inside the current `<Part>` is
        // collected here and all of them get the same name once `<trackName>` is reached.
        private var currentPartStaffIDs: [String] = []

        // `<metaTag name="workTitle">...</metaTag>` / `<metaTag name="composer">...</metaTag>` —
        // MuseScore's own metadata shape, an element with a "name" attribute rather than a
        // distinct element per field (unlike MusicXML's `<work-title>`/`<creator type="...">`).
        private var currentMetaTagName: String?

        // Reset per `<Staff id="N">` (the content-bearing one, a sibling of <Part> not its child).
        private var currentStaffID: String?
        private var measureStartTick = 0
        private var currentBeatsPerMeasure = 4
        private var currentBeatUnit = 4

        // Reset per `<voice>`.
        private var voiceCursorTick = 0

        // Reset per `<Chord>`/`<Rest>`.
        private var inChordOrRest = false
        private var isRest = false
        private var durationType = "quarter"
        private var dots = 0
        private var durationOverrideFraction: Double?
        private var chordNotes: [(pitch: Int, tpc: Int)] = []

        // Reset per `<Note>`.
        private var notePitch: Int?
        private var noteTpc = 14 // defaults to C natural if a file omits <tpc>

        // Reset per `<Harmony>`.
        private var inHarmony = false
        private var harmonyRootTpc: Int?
        private var harmonyName: String?

        func makeRawScore(outputDivisionsPerQuarter: Int) -> RawScore {
            let measureCount = measuresByStaff[staffOrder.first ?? ""]?.count ?? 0
            let order = MuseScoreReader.expandedMeasureOrder(measureCount: measureCount, markers: repeatMarkers)
            let parts = staffOrder.map { id -> RawPart in
                let buckets = measuresByStaff[id] ?? []
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
                return RawPart(id: id, name: trackNameByStaffID[id] ?? "Staff \(id)", notes: notes.sorted { $0.startTick < $1.startTick })
            }
            return RawScore(
                sourceFormat: .museScore, title: title, composer: composer,
                divisionsPerQuarterNote: outputDivisionsPerQuarter,
                tempoMap: tempoMap.sorted { $0.tick < $1.tick },
                timeSignatureMap: timeSignatureMap.sorted { $0.tick < $1.tick },
                keySignatureMap: keySignatureMap.sorted { $0.tick < $1.tick },
                parts: parts, explicitChords: explicitChords.sorted { $0.tick < $1.tick }
            )
        }

        // MARK: XMLParserDelegate

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if elementStack.isEmpty, elementName != "museScore" {
                parseError = MuseScoreReader.MuseScoreError.notMuseScore
                parser.abortParsing()
                return
            }
            if elementName == "museScore" {
                let version = attributeDict["version"] ?? ""
                let majorVersion = version.split(separator: ".").first.map(String.init)
                // Verified against real files from both eras: MuseScore 4.x nests each measure's
                // content in a <voice> element; MuseScore 2.x (2.06, from 2016) has no <voice> at
                // all — Chord/Rest/Clef/KeySig/TimeSig sit directly under <Measure>. Both shapes
                // are handled below (`<Measure>` itself resets the cursor, `<voice>` does too
                // when present) — an unrecognized major version still fails loudly rather than
                // risk a silent wrong parse against a shape never seen.
                guard majorVersion == "2" || majorVersion == "4" else {
                    parseError = MuseScoreReader.MuseScoreError.unsupportedSchemaVersion(version)
                    parser.abortParsing()
                    return
                }
            }
            elementStack.append(elementName)
            text = ""

            switch elementName {
            case "metaTag":
                currentMetaTagName = attributeDict["name"]
            case "Part":
                currentPartStaffIDs = []
            case "Staff":
                if elementStack.dropLast().last == "Part", let id = attributeDict["id"] {
                    currentPartStaffIDs.append(id)
                } else if elementStack.dropLast().last == "Score", let id = attributeDict["id"] {
                    currentStaffID = id
                    staffOrder.append(id)
                    measureStartTick = 0
                    voiceCursorTick = 0
                    currentBeatsPerMeasure = 4
                    currentBeatUnit = 4
                    currentMeasureIndex = -1
                }
            case "Measure":
                // Covers MuseScore 2.x, which has no <voice> wrapper at all (a measure's content
                // sits directly under <Measure>) — <voice>'s own reset below still applies on top
                // of this for 4.x's multiple simultaneous voices, and for 2.x is simply a no-op
                // re-assignment of the same value since no notes intervene between the two.
                voiceCursorTick = measureStartTick
                currentMeasureIndex += 1
                if let currentStaffID {
                    measuresByStaff[currentStaffID, default: []].append(MeasureBucket(startTick: measureStartTick, endTick: measureStartTick))
                }
            case "startRepeat":
                if currentStaffID == staffOrder.first {
                    repeatMarkers.append(RepeatMarker(measureIndex: currentMeasureIndex, direction: .forward, times: nil))
                }
            case "voice":
                voiceCursorTick = measureStartTick
            case "Chord", "Rest":
                inChordOrRest = true
                isRest = elementName == "Rest"
                durationType = "quarter"
                dots = 0
                durationOverrideFraction = nil
                chordNotes = []
            case "duration":
                if inChordOrRest, let z = attributeDict["z"].flatMap(Double.init), let n = attributeDict["n"].flatMap(Double.init), n > 0 {
                    // MuseScore's own exact-fraction override (of a whole note) — used for
                    // full-measure rests (`<durationType>measure</durationType>` alone doesn't
                    // say HOW long "the measure" is) and tuplets; takes priority over the
                    // duration-type-name/dots calculation when present.
                    durationOverrideFraction = z / n
                }
            case "Note":
                notePitch = nil
                noteTpc = 14
            case "Harmony":
                inHarmony = true
                harmonyRootTpc = nil
                harmonyName = nil
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
            case "metaTag":
                switch currentMetaTagName {
                case "workTitle": title = trimmed.isEmpty ? title : trimmed
                case "composer": composer = trimmed.isEmpty ? composer : trimmed
                default: break
                }
            case "trackName":
                if elementStack.dropLast().last == "Part" {
                    for staffID in currentPartStaffIDs { trackNameByStaffID[staffID] = trimmed }
                }
            case "sigN":
                pendingSigN = Int(trimmed)
            case "sigD":
                if let n = pendingSigN, let d = Int(trimmed) {
                    currentBeatsPerMeasure = n
                    currentBeatUnit = d
                    timeSignatureMap.append(RawTimeSignatureEvent(tick: measureStartTick, beatsPerMeasure: n, beatUnit: d))
                    pendingSigN = nil
                }
            case "concertKey":
                keySignatureMap.append(RawKeySignatureEvent(tick: measureStartTick, fifths: Int(trimmed) ?? 0))
            case "tempo":
                if elementStack.dropLast().last == "Tempo", let quarterNotesPerSecond = Double(trimmed), quarterNotesPerSecond > 0 {
                    tempoMap.append(RawTempoEvent(tick: measureStartTick, microsecondsPerQuarter: Int((1_000_000 / quarterNotesPerSecond).rounded())))
                }
            case "durationType":
                if inChordOrRest { durationType = trimmed }
            case "dots":
                if inChordOrRest { dots = Int(trimmed) ?? 0 }
            case "pitch":
                if elementStack.dropLast().last == "Note" { notePitch = Int(trimmed) }
            case "tpc":
                if elementStack.dropLast().last == "Note" { noteTpc = Int(trimmed) ?? 14 }
            case "Note":
                if let pitch = notePitch { chordNotes.append((pitch: pitch, tpc: noteTpc)) }
            case "root":
                if inHarmony { harmonyRootTpc = Int(trimmed) }
            case "name":
                if inHarmony { harmonyName = trimmed }
            case "Harmony":
                inHarmony = false
                if let rootTpc = harmonyRootTpc {
                    let rootSpelling = MuseScoreReader.spelling(pitch: 60, tpc: rootTpc) // pitch irrelevant to step/alter here, octave unused
                    explicitChords.append(RawChordSymbol(tick: voiceCursorTick, rootStep: rootSpelling.step, rootAlter: rootSpelling.alter, kind: harmonyName ?? "major"))
                }
            case "endRepeat":
                if currentStaffID == staffOrder.first {
                    repeatMarkers.append(RepeatMarker(measureIndex: currentMeasureIndex, direction: .backward, times: Int(trimmed)))
                }
            case "Chord", "Rest":
                inChordOrRest = false
                let durationTicks = MuseScoreReader.ticks(durationType: durationType, dots: dots, overrideFraction: durationOverrideFraction)
                if let staffID = currentStaffID, measuresByStaff[staffID]?.isEmpty == false {
                    let lastIndex = measuresByStaff[staffID]!.count - 1
                    if isRest || chordNotes.isEmpty {
                        measuresByStaff[staffID]![lastIndex].notes.append(RawNote(startTick: voiceCursorTick, durationTicks: durationTicks, pitch: 0, isRest: true))
                    } else {
                        for note in chordNotes {
                            let spelling = MuseScoreReader.spelling(pitch: note.pitch, tpc: note.tpc)
                            measuresByStaff[staffID]![lastIndex].notes.append(RawNote(
                                startTick: voiceCursorTick, durationTicks: durationTicks, pitch: note.pitch, spelling: spelling
                            ))
                        }
                    }
                }
                voiceCursorTick += durationTicks
            case "Measure":
                let ticksPerBeatUnit = MuseScoreReader.outputDivisionsPerQuarter * 4 / max(currentBeatUnit, 1)
                measureStartTick += max(currentBeatsPerMeasure, 1) * ticksPerBeatUnit
                if let currentStaffID, measuresByStaff[currentStaffID]?.isEmpty == false {
                    measuresByStaff[currentStaffID]![measuresByStaff[currentStaffID]!.count - 1].endTick = measureStartTick
                }
            default:
                break
            }
        }

        // `<TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>` needs both children.
        private var pendingSigN: Int?

        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
            if self.parseError == nil { self.parseError = MuseScoreReader.MuseScoreError.xmlParseFailed(parseError.localizedDescription) }
        }
    }
}

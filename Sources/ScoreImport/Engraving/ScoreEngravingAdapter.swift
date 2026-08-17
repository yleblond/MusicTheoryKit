import Foundation
import MusicTheoryKit
import PieceModel

/// Converts a `RawScore` (tick-based, not-yet-notated) into a `NotatedScore` (measures of
/// discrete note durations + VexFlow key strings) for display. This is display quantization,
/// not the same as `BeatQuantizer`'s measure/beat grid for `Piece` — the two happen to share
/// the "round ticks to a standard value" idea but serve different consumers (a renderer here,
/// `MelodyEvent.measure/beat` there) and are free to diverge.
///
/// Known v1 limitations (acceptable for a "raw file" sanity-check view, not publication-quality
/// engraving — see the score-import plan's Option A/B discussion):
/// - Notes are clipped to fit within the measure they start in — no ties across a barline.
/// - Simultaneous notes are only grouped into a chord when they share the exact same start tick
///   AND duration; genuinely independent polyphonic voices of differing rhythm are not
///   separated into distinct notated voices, they render sequentially instead.
/// - Always treble clef; multi-staff/clef-per-part is not modeled yet.
public enum ScoreEngravingAdapter {
    /// Renders an already-composed `Piece` (hand-authored, LLM-composed, or the result of
    /// `RawScoreComposer.compose`) the same way an imported file is rendered — rather than
    /// re-implementing measure-segmentation/rest-filling/duration-quantization a second time for
    /// `Piece`'s measure/beat shape, this converts each track's events into synthetic
    /// tick-based `RawNote`s (an arbitrary but internally-consistent 480 ticks/quarter) and
    /// reuses the same `buildMeasures` helper `build(from: RawScore)` is built on. `Piece`'s own
    /// "one time signature/tempo for the whole piece" shape means only one `RawTimeSignatureEvent`
    /// at tick 0 is ever needed here, unlike a real imported file's map.
    public static func build(from piece: Piece) -> NotatedScore {
        let ticksPerQuarter = 480
        let beatsPerMeasure = max(piece.timeSignature.beatsPerMeasure, 1)
        let beatUnit = max(piece.timeSignature.beatUnit, 1)
        let ticksPerBeatUnit = ticksPerQuarter * 4 / beatUnit
        let measureLengthTicks = beatsPerMeasure * ticksPerBeatUnit
        let totalMeasures = piece.sections.reduce(0) { $0 + $1.lengthInMeasures }
        let totalTicks = totalMeasures * measureLengthTicks
        let timeSignatures = [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: beatsPerMeasure, beatUnit: beatUnit)]

        // `minimumTicks: totalTicks` below is what makes a track absent from a LATER section
        // still get that section's worth of silent measures, rather than the part simply
        // ending early and every other part's measures no longer lining up with it.
        let parts = rawParts(from: piece, ticksPerQuarter: ticksPerQuarter, ticksPerBeatUnit: ticksPerBeatUnit, beatsPerMeasure: beatsPerMeasure).map { rawPart in
            NotatedPart(
                id: rawPart.id, name: rawPart.name,
                measures: buildMeasures(notes: rawPart.notes, timeSignatures: timeSignatures, ticksPerQuarter: ticksPerQuarter, minimumTicks: totalTicks)
            )
        }
        return NotatedScore(parts: parts)
    }

    /// Tracks are matched across sections by name (first-seen order) so a multi-section piece's
    /// timeline stays aligned; a section missing a given name contributes no notes of its own
    /// here — the silence for its span comes from `build(from: Piece)`'s `minimumTicks`, passed
    /// to `buildMeasures` so that section's measures still get generated (as rests) for every
    /// part, not just the ones with real notes in it.
    private static func rawParts(from piece: Piece, ticksPerQuarter: Int, ticksPerBeatUnit: Int, beatsPerMeasure: Int) -> [RawPart] {
        var order: [String] = []
        for section in piece.sections {
            for track in section.tracks where !order.contains(track.name) { order.append(track.name) }
        }

        var notesByName: [String: [RawNote]] = Dictionary(uniqueKeysWithValues: order.map { ($0, []) })
        var sectionStartBeat = 0.0
        for section in piece.sections {
            for track in section.tracks {
                let notes = track.melodyEvents.map { event -> RawNote in
                    let localBeat = section.absoluteBeat(measure: event.measure, beat: event.beat, beatsPerMeasure: beatsPerMeasure)
                    let startTick = Int(((sectionStartBeat + localBeat) * Double(ticksPerBeatUnit)).rounded())
                    let durationTicks = max(Int((event.durationBeats * Double(ticksPerBeatUnit)).rounded()), 1)
                    return RawNote(startTick: startTick, durationTicks: durationTicks, pitch: event.pitch, velocity: event.velocity)
                }
                notesByName[track.name, default: []].append(contentsOf: notes)
            }
            sectionStartBeat += Double(section.lengthInMeasures * beatsPerMeasure)
        }

        return order.map { name in
            RawPart(id: name, name: name, notes: (notesByName[name] ?? []).sorted { $0.startTick < $1.startTick })
        }
    }

    public static func build(from rawScore: RawScore) -> NotatedScore {
        let ticksPerQuarter = max(rawScore.divisionsPerQuarterNote, 1)
        let timeSignatures = rawScore.timeSignatureMap.isEmpty
            ? [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)]
            : rawScore.timeSignatureMap.sorted { $0.tick < $1.tick }

        let parts = rawScore.parts.map { rawPart in
            NotatedPart(
                id: rawPart.id, name: rawPart.name,
                measures: buildMeasures(notes: rawPart.notes, timeSignatures: timeSignatures, ticksPerQuarter: ticksPerQuarter)
            )
        }
        return NotatedScore(parts: parts)
    }

    // MARK: - Measure segmentation

    /// `minimumTicks` (default 0, i.e. no effect on the real-import path in `build(from:
    /// RawScore)`) forces at least that many ticks' worth of measures to be generated even past
    /// this part's own last note — used only by `build(from: Piece)`, so a track absent from a
    /// later section still gets that section's silent measures instead of ending early and
    /// throwing every other part's measure alignment off.
    private static func buildMeasures(notes: [RawNote], timeSignatures: [RawTimeSignatureEvent], ticksPerQuarter: Int, minimumTicks: Int = 0) -> [NotatedMeasure] {
        let sortedNotes = notes.filter { !$0.isRest }.sorted { $0.startTick < $1.startTick }
        guard !sortedNotes.isEmpty || minimumTicks > 0 else { return [] }

        var measures: [NotatedMeasure] = []
        var measureStart = 0
        var noteIndex = 0
        var timeSignatureIndex = 0

        // Driven by how many *notes* remain (or `minimumTicks`, for a Piece part with no notes
        // at all in one or more sections), not by notes' (possibly long, since-clipped) raw end
        // ticks — a note that would have spanned past a measure gets clipped to fit (see the
        // type's doc comment on ties), so its discarded tail must NOT spawn extra trailing
        // rest-only measures. Each iteration is guaranteed to make progress: either it consumes
        // the next unconsumed note once `measureEnd` grows past its start tick, or `measureEnd`
        // itself keeps growing toward `minimumTicks`, so this always terminates.
        while noteIndex < sortedNotes.count || measureStart < minimumTicks {
            while timeSignatureIndex + 1 < timeSignatures.count, timeSignatures[timeSignatureIndex + 1].tick <= measureStart {
                timeSignatureIndex += 1
            }
            let timeSignature = timeSignatures[timeSignatureIndex]
            let ticksPerBeatUnit = ticksPerQuarter * 4 / max(timeSignature.beatUnit, 1)
            let measureLength = max(timeSignature.beatsPerMeasure, 1) * ticksPerBeatUnit
            let measureEnd = measureStart + measureLength

            var positions: [(startTick: Int, durationTicks: Int, notes: [(pitch: Int, spelling: RawSpelling?)])] = []
            while noteIndex < sortedNotes.count, sortedNotes[noteIndex].startTick < measureEnd {
                let note = sortedNotes[noteIndex]
                if !positions.isEmpty, positions[positions.count - 1].startTick == note.startTick,
                   positions[positions.count - 1].durationTicks == note.durationTicks {
                    positions[positions.count - 1].notes.append((note.pitch, note.spelling))
                } else {
                    positions.append((note.startTick, note.durationTicks, [(note.pitch, note.spelling)]))
                }
                noteIndex += 1
            }

            var measureNotes: [NotatedNote] = []
            var cursor = measureStart
            for position in positions {
                if position.startTick > cursor {
                    measureNotes.append(contentsOf: rests(from: cursor, to: position.startTick, ticksPerQuarter: ticksPerQuarter))
                }
                let clippedDuration = min(position.durationTicks, measureEnd - position.startTick)
                measureNotes.append(NotatedNote(
                    id: UUID().uuidString, isRest: false,
                    keys: position.notes.map { vexFlowKey(forPitch: $0.pitch, spelling: $0.spelling) },
                    duration: quantizedDuration(ticks: clippedDuration, ticksPerQuarter: ticksPerQuarter),
                    pitches: position.notes.map(\.pitch)
                ))
                cursor = position.startTick + clippedDuration
            }
            if cursor < measureEnd {
                measureNotes.append(contentsOf: rests(from: cursor, to: measureEnd, ticksPerQuarter: ticksPerQuarter))
            }

            measures.append(NotatedMeasure(beatsPerMeasure: timeSignature.beatsPerMeasure, beatUnit: timeSignature.beatUnit, notes: measureNotes))
            measureStart = measureEnd
        }
        return measures
    }

    // MARK: - Duration quantization

    /// (duration in quarter notes, VexFlow code), descending — used both to find the nearest
    /// standard value for an actual note and to greedily fill rest gaps largest-first.
    private static let standardDurations: [(quarters: Double, code: String)] = [
        (4.0, "w"), (3.0, "hd"), (2.0, "h"), (1.5, "qd"), (1.0, "q"),
        (0.75, "8d"), (0.5, "8"), (0.375, "16d"), (0.25, "16"), (0.125, "32"),
    ]

    private static func quantizedDuration(ticks: Int, ticksPerQuarter: Int) -> String {
        guard ticks > 0 else { return "32" }
        let quarters = Double(ticks) / Double(ticksPerQuarter)
        let best = standardDurations.min { abs($0.quarters - quarters) < abs($1.quarters - quarters) }
        return best?.code ?? "q"
    }

    private static func ticks(forQuarters quarters: Double, ticksPerQuarter: Int) -> Int {
        Int((quarters * Double(ticksPerQuarter)).rounded())
    }

    /// Fills a gap with rests, picking the largest standard duration that fits at each step
    /// (never overshooting past `to`) — a `safetyLimit` bounds the loop defensively, since a
    /// pathological tick value should degrade to "one oddly-sized rest" rather than hang.
    private static func rests(from start: Int, to end: Int, ticksPerQuarter: Int) -> [NotatedNote] {
        var result: [NotatedNote] = []
        var cursor = start
        var safetyLimit = 64
        while cursor < end, safetyLimit > 0 {
            safetyLimit -= 1
            let remaining = end - cursor
            let chosen = standardDurations.first { ticks(forQuarters: $0.quarters, ticksPerQuarter: ticksPerQuarter) <= remaining }
            let code = chosen?.code ?? "32"
            let consumed = max(chosen.map { ticks(forQuarters: $0.quarters, ticksPerQuarter: ticksPerQuarter) } ?? remaining, 1)
            result.append(NotatedNote(id: UUID().uuidString, isRest: true, duration: code))
            cursor += consumed
        }
        return result
    }

    // MARK: - Pitch spelling

    private static func vexFlowAccidentalCode(fromAlter alter: Int) -> String {
        switch alter {
        case -2: return "bb"
        case -1: return "b"
        case 1: return "#"
        case 2: return "##"
        default: return ""
        }
    }

    private static func vexFlowAccidentalCode(_ accidental: Accidental) -> String {
        vexFlowAccidentalCode(fromAlter: accidental.rawValue)
    }

    /// The source's own spelling when available (MusicXML/MuseScore); otherwise a best-guess
    /// canonical spelling computed from the bare MIDI pitch class (MIDI has no letter-name
    /// notion of its own).
    private static func vexFlowKey(forPitch pitch: Int, spelling: RawSpelling?) -> String {
        if let spelling {
            return "\(spelling.step.lowercased())\(vexFlowAccidentalCode(fromAlter: spelling.alter))/\(spelling.octave)"
        }
        let pitchClass = PitchClass(((pitch % 12) + 12) % 12)
        let spelled = DiatonicSpelling.canonicalSpelling(forPitchClass: pitchClass)
        let octave = pitch / 12 - 1
        let letter = String(describing: spelled.letter).lowercased()
        return "\(letter)\(vexFlowAccidentalCode(spelled.accidental))/\(octave)"
    }
}

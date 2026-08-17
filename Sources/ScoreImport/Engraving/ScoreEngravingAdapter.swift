import Foundation
import MusicTheoryKit

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

    private static func buildMeasures(notes: [RawNote], timeSignatures: [RawTimeSignatureEvent], ticksPerQuarter: Int) -> [NotatedMeasure] {
        let sortedNotes = notes.filter { !$0.isRest }.sorted { $0.startTick < $1.startTick }
        guard !sortedNotes.isEmpty else { return [] }

        var measures: [NotatedMeasure] = []
        var measureStart = 0
        var noteIndex = 0
        var timeSignatureIndex = 0

        // Driven by how many *notes* remain, not by their (possibly long, since-clipped) raw
        // end ticks — a note that would have spanned past a measure gets clipped to fit
        // (see the type's doc comment on ties), so its discarded tail must NOT spawn extra
        // trailing rest-only measures. Each iteration is guaranteed to consume at least the
        // next unconsumed note once `measureEnd` grows past its start tick, so this terminates.
        while noteIndex < sortedNotes.count {
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

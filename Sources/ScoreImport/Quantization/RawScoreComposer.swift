import Foundation
import MusicTheoryKit
import PieceModel

/// Turns a `RawScore` into a playable `Piece` — deterministic quantization + batch chord/key
/// inference, never an LLM (unlike `LLMPieceComposer`, whose SoundTrack-\>Piece conversion is
/// actually an LLM's own judgment call end to end; only its "validated DTO, warnings instead of
/// throwing" idiom is mirrored here, not its logic — see the score-import plan).
///
/// v1 simplifications, each producing a warning when actually triggered by the source file
/// (rather than silently dropping information):
/// - **One time signature for the whole piece.** `Piece.timeSignature` is a single top-level
///   field — there is nowhere to hang a per-section time signature even though `RawScore` can
///   carry several. The first declared time signature (or 4/4) is used throughout; a source
///   file with more than one is a real, audible simplification, not just a display nuance.
/// - **One section, one detected key/mode for the whole piece.** Mid-piece key-signature
///   changes are not split into separate `Section`s in v1.
public enum RawScoreComposer {
    public static func compose(from rawScore: RawScore) -> (Piece?, [String]) {
        var warnings: [String] = []
        let allNotes = rawScore.parts.flatMap(\.notes).filter { !$0.isRest }
        guard !allNotes.isEmpty else {
            return (nil, ["no notes found in the imported file"])
        }

        let ticksPerQuarter = max(rawScore.divisionsPerQuarterNote, 1)
        let timeSignature = resolvedTimeSignature(from: rawScore, warnings: &warnings)
        let ticksPerBeatUnit = ticksPerQuarter * 4 / max(timeSignature.beatUnit, 1)
        let measureLengthTicks = max(timeSignature.beatsPerMeasure, 1) * ticksPerBeatUnit
        let subdivisionsPerBeat = RhythmStructure().subdivisionsPerBeat

        if Set(rawScore.keySignatureMap.map { "\($0.fifths):\($0.isMinor)" }).count > 1 {
            warnings.append("the source declares more than one key signature; only one detected mode is used for the whole piece")
        }

        let lastTick = allNotes.map { $0.startTick + $0.durationTicks }.max() ?? 0
        let lengthInMeasures = max(Int((Double(lastTick) / Double(measureLengthTicks)).rounded(.up)), 1)
        let totalTicks = lengthInMeasures * measureLengthTicks

        let detectedMode = KeyModeDetector.detect(notes: allNotes.map { (pitch: $0.pitch, durationTicks: $0.durationTicks) })
        if detectedMode == nil {
            warnings.append("could not confidently detect a key; defaulting to C major")
        }
        let mode = detectedMode ?? ModeReference(tonic: 0, scaleID: "ionian")

        let chordProgression = resolveChordProgression(
            rawScore: rawScore, allNotes: allNotes, totalTicks: totalTicks,
            measureLengthTicks: measureLengthTicks, ticksPerBeatUnit: ticksPerBeatUnit, warnings: &warnings
        )
        if chordProgression.isEmpty {
            warnings.append("no chords could be confidently detected")
        }

        let tracks = rawScore.parts.enumerated().map { index, part in
            Track(
                name: part.name ?? "Track \(index + 1)",
                instrument: part.instrumentHint ?? "",
                melodyEvents: BeatQuantizer.melodyEvents(
                    from: part.notes, ticksPerQuarter: ticksPerQuarter,
                    measureLengthTicks: measureLengthTicks, ticksPerBeatUnit: ticksPerBeatUnit,
                    subdivisionsPerBeat: subdivisionsPerBeat
                )
            )
        }

        let section = Section(
            name: "Section 1", lengthInMeasures: lengthInMeasures, mode: mode, chordProgression: chordProgression, tracks: tracks
        )
        let tempoBPM = rawScore.tempoMap.first?.beatsPerMinute ?? 120
        let piece = Piece(
            title: rawScore.title?.isEmpty == false ? rawScore.title! : "Imported piece",
            composer: rawScore.composer,
            timeSignature: timeSignature,
            tempoBPM: tempoBPM,
            key: mode,
            sections: [section]
        )
        return (piece, warnings)
    }

    private static func resolvedTimeSignature(from rawScore: RawScore, warnings: inout [String]) -> TimeSignature {
        let distinctSignatures = Set(rawScore.timeSignatureMap.map { "\($0.beatsPerMeasure)/\($0.beatUnit)" })
        if distinctSignatures.count > 1 {
            warnings.append("the source changes time signature partway through; using the first one (\(distinctSignatures.sorted().first ?? "4/4")) for the whole piece")
        }
        guard let first = rawScore.timeSignatureMap.sorted(by: { $0.tick < $1.tick }).first else {
            return .commonTime
        }
        return TimeSignature(beatsPerMeasure: first.beatsPerMeasure, beatUnit: first.beatUnit)
    }

    private static func resolveChordProgression(
        rawScore: RawScore, allNotes: [RawNote], totalTicks: Int,
        measureLengthTicks: Int, ticksPerBeatUnit: Int, warnings: inout [String]
    ) -> [ChordEvent] {
        if !rawScore.explicitChords.isEmpty {
            let sorted = rawScore.explicitChords.sorted { $0.tick < $1.tick }
            return sorted.enumerated().map { index, symbol in
                let endTick = index + 1 < sorted.count ? sorted[index + 1].tick : totalTicks
                let (measure, beat) = BeatQuantizer.measureBeat(forTick: symbol.tick, measureLengthTicks: measureLengthTicks, ticksPerBeatUnit: ticksPerBeatUnit)
                let durationBeats = Double(max(endTick - symbol.tick, 1)) / Double(ticksPerBeatUnit)
                guard let templateID = ChordSliceDetector.chordVocabularyID(forExplicitKind: symbol.kind) else {
                    warnings.append("unrecognized chord quality '\(symbol.kind)' from the source; used a plain major triad instead")
                    return ChordEvent(
                        measure: measure, beat: beat, durationBeats: durationBeats,
                        chord: ChordReference(root: pitchClass(step: symbol.rootStep, alter: symbol.rootAlter).value, chordTemplateID: "Ma")
                    )
                }
                return ChordEvent(
                    measure: measure, beat: beat, durationBeats: durationBeats,
                    chord: ChordReference(root: pitchClass(step: symbol.rootStep, alter: symbol.rootAlter).value, chordTemplateID: templateID)
                )
            }
        }

        return ChordSliceDetector.detectChordProgression(
            notes: allNotes.map { (startTick: $0.startTick, durationTicks: $0.durationTicks, pitch: $0.pitch) },
            totalTicks: totalTicks, sliceTicks: measureLengthTicks,
            ticksPerBeatUnit: ticksPerBeatUnit, measureLengthTicks: measureLengthTicks
        )
    }

    private static func pitchClass(step: String, alter: Int) -> PitchClass {
        let naturals: [String: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        return PitchClass((naturals[step.uppercased()] ?? 0) + alter)
    }
}

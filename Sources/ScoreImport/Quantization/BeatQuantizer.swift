import Foundation
import PieceModel

/// Snaps `RawScore` ticks onto `Piece`'s measure/beat grid. This is a deliberate lossy step —
/// the same idea `LLMPieceComposer` already applies when turning a `SoundTrack`'s wall-clock
/// note events into a measure/beat `Piece`, just via a fixed grid here instead of an LLM's own
/// judgment. `RawScore` itself is kept around unchanged (see the score-import plan) precisely so
/// this can be re-run with a different grid later without re-parsing the source file.
public enum BeatQuantizer {
    /// Converts an absolute tick position into a 1-based (measure, beat) pair.
    public static func measureBeat(forTick tick: Int, measureLengthTicks: Int, ticksPerBeatUnit: Int) -> (measure: Int, beat: Double) {
        guard measureLengthTicks > 0, ticksPerBeatUnit > 0 else { return (1, 1) }
        let measureIndex = tick / measureLengthTicks
        let tickWithinMeasure = tick % measureLengthTicks
        let beat = Double(tickWithinMeasure) / Double(ticksPerBeatUnit) + 1
        return (measureIndex + 1, beat)
    }

    /// Rounds `tick` to the nearest grid point, `subdivisionsPerBeat` points per quarter-note
    /// beat (4 = sixteenth notes, matching `RhythmStructure`'s own default).
    public static func snapped(tick: Int, ticksPerQuarter: Int, subdivisionsPerBeat: Int) -> Int {
        guard subdivisionsPerBeat > 0, ticksPerQuarter > 0 else { return tick }
        let gridTicks = max(ticksPerQuarter / subdivisionsPerBeat, 1)
        return Int((Double(tick) / Double(gridTicks)).rounded()) * gridTicks
    }

    /// Converts one part's raw notes into `MelodyEvent`s on the given grid — rests are dropped
    /// (silence needs no `MelodyEvent`), and a note's snapped duration is floored to one grid
    /// step so quantization can never collapse it to zero.
    public static func melodyEvents(
        from notes: [RawNote], ticksPerQuarter: Int, measureLengthTicks: Int, ticksPerBeatUnit: Int, subdivisionsPerBeat: Int
    ) -> [MelodyEvent] {
        let minDurationTicks = max(ticksPerQuarter / subdivisionsPerBeat, 1)
        return notes.filter { !$0.isRest }.map { note in
            let snappedStart = snapped(tick: note.startTick, ticksPerQuarter: ticksPerQuarter, subdivisionsPerBeat: subdivisionsPerBeat)
            let snappedEnd = snapped(tick: note.startTick + note.durationTicks, ticksPerQuarter: ticksPerQuarter, subdivisionsPerBeat: subdivisionsPerBeat)
            let durationTicks = max(snappedEnd - snappedStart, minDurationTicks)
            let (measure, beat) = measureBeat(forTick: snappedStart, measureLengthTicks: measureLengthTicks, ticksPerBeatUnit: ticksPerBeatUnit)
            let durationBeats = Double(durationTicks) / Double(ticksPerBeatUnit)
            return MelodyEvent(measure: measure, beat: beat, durationBeats: durationBeats, pitch: note.pitch, velocity: note.velocity)
        }
    }
}

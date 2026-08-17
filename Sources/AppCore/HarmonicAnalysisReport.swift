import Foundation
import MusicTheoryKit
import PieceModel
import RecognitionEngine

/// One row of a harmonic analysis, grouped by measure for display (see the "Analyse" tab in
/// `PieceDetailView`).
public struct HarmonicAnalysisEntry: Identifiable, Equatable, Sendable {
    public var id: String
    public var measure: Int
    public var beat: Double
    public var chordSymbol: String
    public var romanNumeral: String
    public var confidence: RomanNumeralConfidence

    public init(id: String = UUID().uuidString, measure: Int, beat: Double, chordSymbol: String, romanNumeral: String, confidence: RomanNumeralConfidence) {
        self.id = id
        self.measure = measure
        self.beat = beat
        self.chordSymbol = chordSymbol
        self.romanNumeral = romanNumeral
        self.confidence = confidence
    }
}

/// Batch driver for `RomanNumeralAnalyzer` — the thin `PieceModel`-unwrapping adapter that keeps
/// `RecognitionEngine` itself `PieceModel`-free (same split as `pitchDisplayState` elsewhere in
/// this module).
public enum HarmonicAnalysisReport {
    public static func build(from piece: Piece) -> [HarmonicAnalysisEntry] {
        var entries: [HarmonicAnalysisEntry] = []
        for section in piece.sections {
            guard let mode = section.mode.resolve() else { continue }
            let modeTones = mode.pitchClasses.map(\.value)
            let events = section.chordProgression
            for (index, event) in events.enumerated() {
                guard let chord = event.chord.resolve() else { continue }
                let lookaheadCount = min(3, events.count - index - 1)
                let lookahead = (0..<lookaheadCount).map { events[index + 1 + $0].chord.root }
                let label = RomanNumeralAnalyzer.label(
                    chordRoot: event.chord.root, chordTemplateID: event.chord.chordTemplateID,
                    keyTonic: section.mode.tonic, modeTones: modeTones,
                    lookahead: lookahead
                )
                entries.append(HarmonicAnalysisEntry(
                    measure: event.measure, beat: event.beat,
                    chordSymbol: chordSymbol(for: chord),
                    romanNumeral: label.numeral, confidence: label.confidence
                ))
            }
        }
        return entries
    }

    private static let pitchNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// A short letter-name chord symbol (e.g. "G#m7b5") for display alongside the roman numeral.
    private static func chordSymbol(for chord: Chord) -> String {
        let rootName = pitchNames[chord.root.value]
        let suffix: String
        switch chord.template.id {
        case "Ma": suffix = ""
        case "mi": suffix = "m"
        case "dim": suffix = "dim"
        case "aug": suffix = "+"
        case "7": suffix = "7"
        case "Ma7": suffix = "Ma7"
        case "mi7": suffix = "m7"
        case "mi7b5": suffix = "m7b5"
        case "dim7": suffix = "dim7"
        case "7#5": suffix = "+7"
        case "Ma7#5": suffix = "+Ma7"
        case "miMa7": suffix = "mMa7"
        default: suffix = chord.template.id
        }
        return rootName + suffix
    }
}

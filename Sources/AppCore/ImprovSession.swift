import Foundation
import Observation
import MusicTheoryKit
import PieceModel
import AudioEngine
import MIDIEngine
import RecognitionEngine

/// The whole app's state and behavior, independent of any presentation layer. A CLI
/// front-end drives this today by calling its methods and reading its published state;
/// a future SwiftUI front-end can bind to the same instance directly (it's `@Observable`)
/// without any of this logic moving or changing.
// `@unchecked Sendable`: mutated from the CLI's main thread and from the MIDI/playback
// callback threads, but never truly concurrently for this tool's single-user REPL usage
// (worst case is an interleaved log line, not corrupted state).
@Observable
public final class ImprovSession: @unchecked Sendable {
    public private(set) var piece: Piece?
    public private(set) var isPlaying = false
    public private(set) var isListening = false
    public private(set) var listenOnly = false
    public private(set) var lastMIDIEvent: MIDINoteEvent?
    public private(set) var recognizedChord: RecognizedChord?
    public private(set) var recognizedModes: [RecognizedMode] = []
    /// Human-readable status/event lines, oldest first. A CLI prints new entries as they
    /// arrive; a future UI could bind this straight to a scrolling console view.
    public private(set) var log: [String] = []

    private let player = PiecePlayer()
    private var listener: MIDIInputListener?
    private let recognizer = RecognitionEngine()

    public enum SessionError: Error, CustomStringConvertible {
        case noPieceLoaded
        public var description: String {
            switch self {
            case .noPieceLoaded: return "no piece loaded — try 'load-demo' or 'load <path>'"
            }
        }
    }

    public init() {}

    public func start() throws {
        try player.start()
        append("Audio engine started.")
    }

    public func loadDemoPiece() {
        piece = Self.iiVIDemoPiece()
        append("Loaded demo piece: \(piece!.title)")
    }

    public func loadPiece(fromJSONFile path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try JSONDecoder().decode(Piece.self, from: data)
        piece = decoded
        append("Loaded piece from \(path): \(decoded.title)")
    }

    public func savePiece(toJSONFile path: String) throws {
        guard let piece else { throw SessionError.noPieceLoaded }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(piece)
        try data.write(to: URL(fileURLWithPath: path))
        append("Saved piece to \(path).")
    }

    public func play() throws {
        guard let piece else { throw SessionError.noPieceLoaded }
        let notes = piece.renderedNotes()
        let duration = PiecePlayer.totalDuration(of: notes)
        player.play(notes)
        isPlaying = true
        append("Playing '\(piece.title)': \(notes.count) notes, \(String(format: "%.1f", duration))s.")
        // `.global()`, not `.main`: a blocking-readLine REPL never pumps the main run
        // loop, so a `.main` timer would simply never fire.
        DispatchQueue.global().asyncAfter(deadline: .now() + duration + 0.2) { [weak self] in
            self?.isPlaying = false
            self?.append("Playback finished.")
        }
    }

    public func availableMIDISources() -> [String] {
        MIDIInputListener.sourceNames()
    }

    /// Starts listening to every visible MIDI source. When `listenOnly` is true, incoming
    /// notes are logged but not sounded — for a physical keyboard that already makes its
    /// own sound, where the app only needs to see what's played (future recognition).
    public func startListening(listenOnly: Bool) throws {
        self.listenOnly = listenOnly
        let newListener = try MIDIInputListener { [weak self] event in
            self?.handleIncomingMIDIEvent(event)
        }
        newListener.connectAllSources()
        listener = newListener
        isListening = true
        append("Listening to MIDI (\(listenOnly ? "listen-only, no sound" : "sound through the app")).")
    }

    /// Everything that happens per incoming MIDI event: logging, feeding the recognizer,
    /// and (unless `listenOnly`) sounding the note. Extracted out of the `MIDIInputListener`
    /// closure so it's directly callable from tests without needing real CoreMIDI input.
    func handleIncomingMIDIEvent(_ event: MIDINoteEvent) {
        lastMIDIEvent = event
        append("MIDI \(event.kind == .noteOn ? "on " : "off")pitch=\(event.pitch) vel=\(event.velocity) ch=\(event.channel)")

        switch event.kind {
        case .noteOn: recognizer.noteOn(pitch: event.pitch)
        case .noteOff: recognizer.noteOff(pitch: event.pitch)
        }
        refreshRecognition()

        guard !listenOnly else { return }
        switch event.kind {
        case .noteOn: player.startNote(pitch: event.pitch, velocity: event.velocity, channel: event.channel)
        case .noteOff: player.stopNote(pitch: event.pitch, channel: event.channel)
        }
    }

    public func stopListening() {
        guard isListening else { return }
        listener = nil
        isListening = false
        recognizer.reset()
        recognizedChord = nil
        recognizedModes = []
        append("Stopped listening to MIDI.")
    }

    /// Re-runs chord/mode recognition and logs a line only when the result actually
    /// changed, so holding a chord down doesn't spam the log on every repeated note.
    private func refreshRecognition() {
        let chord = recognizer.recognizeChord()
        if chord != recognizedChord {
            recognizedChord = chord
            append(chord.map { "Chord: \(Self.describe($0))" } ?? "Chord: (none)")
        }

        let modes = recognizer.recognizeModes()
        if modes != recognizedModes {
            recognizedModes = modes
            if !modes.isEmpty {
                append("Mode candidates: " + modes.map(Self.describe).joined(separator: ", "))
            }
        }
    }

    private static func describe(_ chord: RecognizedChord) -> String {
        let slash = chord.bass != chord.root ? "/\(chord.bass.name())" : ""
        return "\(chord.root.name())\(chord.chordTemplateID)\(slash) (\(Int(chord.confidence * 100))%)"
    }

    private static func describe(_ mode: RecognizedMode) -> String {
        let name = ScaleLibrary.byID(mode.scaleID)?.popularName ?? mode.scaleID
        return "\(mode.tonic.name()) \(name) (\(Int(mode.confidence * 100))%)"
    }

    private func append(_ message: String) {
        log.append(message)
    }

    /// A minimal ii-V-I in C major — Dm7-G7-Cmaj7 with an arpeggio melody — used as a
    /// ready-to-play piece without needing a JSON file on hand.
    public static func iiVIDemoPiece() -> Piece {
        let key = ModeReference(tonic: 0, scaleID: "ionian")

        let chordProgression = [
            ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 2, chordTemplateID: "mi7")),
            ChordEvent(measure: 2, beat: 1, durationBeats: 4, chord: ChordReference(root: 7, chordTemplateID: "7")),
            ChordEvent(measure: 3, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma7"), playingStyle: .arpeggioUp),
        ]

        let melodyEvents = [
            MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 62),
            MelodyEvent(measure: 1, beat: 2, durationBeats: 1, pitch: 65),
            MelodyEvent(measure: 1, beat: 3, durationBeats: 1, pitch: 69),
            MelodyEvent(measure: 1, beat: 4, durationBeats: 1, pitch: 72),
            MelodyEvent(measure: 2, beat: 1, durationBeats: 1, pitch: 55),
            MelodyEvent(measure: 2, beat: 2, durationBeats: 1, pitch: 59),
            MelodyEvent(measure: 2, beat: 3, durationBeats: 1, pitch: 62),
            MelodyEvent(measure: 2, beat: 4, durationBeats: 1, pitch: 65),
            MelodyEvent(measure: 3, beat: 1, durationBeats: 1, pitch: 60),
            MelodyEvent(measure: 3, beat: 2, durationBeats: 1, pitch: 64),
            MelodyEvent(measure: 3, beat: 3, durationBeats: 1, pitch: 67),
            MelodyEvent(measure: 3, beat: 4, durationBeats: 2, pitch: 72),
        ]

        let melodyTrack = Track(name: "melody", instrument: "piano", melodyEvents: melodyEvents)
        let section = Section(name: "A", lengthInMeasures: 3, mode: key, chordProgression: chordProgression, tracks: [melodyTrack])
        return Piece(title: "ii-V-I demo", tempoBPM: 96, key: key, sections: [section])
    }
}

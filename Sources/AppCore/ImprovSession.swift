import Foundation
import Observation
import MusicTheoryKit
import PieceModel
import AudioEngine
import MIDIEngine
import RecognitionEngine
import LLMEngine

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
    /// Every MIDI pitch (0...127) currently held down — for drawing a keyboard, not just
    /// reacting to the single most recent event like `lastMIDIEvent` does.
    public private(set) var heldPitches: Set<Int> = []
    /// Which entry of `availableMIDISources()` `startListening` should connect to — `nil`
    /// (the default) means "connect every visible source", same as the original behavior
    /// before source selection existed. Set via `useMIDISource(atIndex:)`.
    public private(set) var selectedMIDISourceIndex: Int?
    /// The current piece's chord progression, flattened to absolute seconds — computed
    /// once when `play()` starts, so a UI can show "where we are" without recomputing it
    /// every frame. Empty when nothing has ever been played.
    public private(set) var playbackTimeline: [TimedChordEvent] = []
    /// Which entry of `playbackTimeline` is sounding right now, updated live while playing;
    /// `nil` before/after playback (or if the piece has no chords at all).
    public private(set) var playbackCurrentChordIndex: Int?
    /// Every pitch currently sounding because of `play()` — the piece-playback counterpart
    /// to `heldPitches` (which only reflects live MIDI input), so a UI can draw a second,
    /// separate keyboard for "what the composition is playing right now".
    public private(set) var playbackHeldPitches: Set<Int> = []
    /// Human-readable status/event lines, oldest first. A CLI prints new entries as they
    /// arrive; a future UI could bind this straight to a scrolling console view.
    public private(set) var log: [String] = []
    /// The folder last listed with `listSampleFiles`, and the `.sf2`/`.dls`/`.aupreset`
    /// files found in it — kept here (not just returned) so a future UI could show a
    /// picker over `sampleFiles` without re-scanning the folder itself.
    public private(set) var sampleFolder: String?
    public private(set) var sampleFiles: [String] = []
    /// The folder last listed with `listPieceFiles`, and the `.json` piece files found in
    /// it — mirrors `sampleFolder`/`sampleFiles`.
    public private(set) var pieceFolder: String?
    public private(set) var pieceFiles: [String] = []
    /// Full path the current `piece` was last loaded from or saved to — what a bare
    /// `savePiece()` (no name) re-saves to. `nil` until a load/save-as has happened once.
    public private(set) var currentPieceFilePath: String?
    /// A pasted text (e.g. a poem) to compose a piece from — see `composeFromText()`.
    public private(set) var sourceText: String?
    /// The folder last listed with `listLLMConnections`, and the `.json` connection
    /// descriptors found in it — mirrors `sampleFolder`/`sampleFiles`.
    public private(set) var llmConnectionsFolder: String?
    public private(set) var llmConnections: [String] = []
    public private(set) var currentLLMConnection: LLMConnection?

    private let player = PiecePlayer()
    private var listener: MIDIInputListener?
    private let recognizer = RecognitionEngine()
    /// Serializes `handleIncomingMIDIEvent` regardless of which thread calls it. It used to
    /// run wherever the caller happened to be — fine while the only callers were the single
    /// CoreMIDI callback stream and one-at-a-time REPL `press`/`release` commands, both
    /// effectively serial in practice. `keyboard-source`'s auto-release timers broke that
    /// assumption: typing several notes in quick succession schedules several independent
    /// `DispatchQueue.global()` releases, which can then fire concurrently with each other
    /// and with a fresh `pressKey` — genuine concurrent mutation of `recognizer`/`heldPitches`
    /// from multiple threads, and crashed with a bad pointer dereference in
    /// `RecognitionEngine.noteOff` in the field, not just in testing this time.
    private let liveInputQueue = DispatchQueue(label: "ImprovSession.liveInput")
    /// Bumped on every `play()` call; each playback's scheduled callbacks capture the value
    /// current at the time and check it before mutating state, so a stale callback from an
    /// earlier (or interrupted) playback can never clobber a newer one's `playbackHeldPitches`
    /// / `playbackCurrentChordIndex` / `isPlaying`.
    private var playbackGeneration = 0
    /// Every `play()`-scheduled UI-state update (`playbackHeldPitches`/`playbackCurrentChordIndex`
    /// /`isPlaying`) runs on this one serial queue instead of `.global()`. A piece routinely
    /// has several notes starting at the exact same deadline (a whole chord struck at once),
    /// which `.global()`'s concurrent worker threads would then mutate `playbackHeldPitches`
    /// (a `Set`) from in parallel with no synchronization — a genuine data race that crashed
    /// with memory corruption in testing, not just a benign "worst case interleaved log line"
    /// like the single-threaded MIDI-callback writes to `heldPitches` elsewhere in this class.
    private let playbackStateQueue = DispatchQueue(label: "ImprovSession.playbackState")

    public enum SessionError: Error, CustomStringConvertible {
        case noPieceLoaded
        case noSampleFolderListed
        case invalidSampleIndex
        case noPieceFolderListed
        case invalidPieceIndex
        case noCurrentPieceFile
        case noLLMConnectionsFolderListed
        case invalidLLMConnectionIndex
        case noSourceText
        case noLLMConnectionSelected
        case llmComposeFailed([String])
        case invalidMIDISourceIndex
        public var description: String {
            switch self {
            case .noPieceLoaded: return "no piece loaded — try 'load-demo' or 'load <path>'"
            case .noSampleFolderListed: return "no sample folder listed yet — try 'samples <folder>' first"
            case .invalidSampleIndex: return "no sample at that index"
            case .noPieceFolderListed: return "no piece folder listed yet — try 'pieces <folder>' first"
            case .invalidPieceIndex: return "no piece at that index"
            case .noCurrentPieceFile: return "this piece was never loaded from or saved to a file — try 'save-as <name>'"
            case .noLLMConnectionsFolderListed: return "no LLM connections folder listed yet — try 'llm-connections <folder>' first"
            case .invalidLLMConnectionIndex: return "no LLM connection at that index"
            case .noSourceText: return "no source text set — try 'paste-text' first"
            case .noLLMConnectionSelected: return "no LLM connection selected — try 'use-llm <n|name>' first"
            case .llmComposeFailed(let warnings): return "composition failed: \(warnings.joined(separator: "; "))"
            case .invalidMIDISourceIndex: return "no MIDI source at that index — try 'sources' first"
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

    /// Starts a blank piece (no sections yet) — the entry point for composing one, by hand
    /// or via `composeFromText()`, rather than loading an existing file.
    public func newPiece(title: String, tempoBPM: Double = 100, key: ModeReference = ModeReference(tonic: 0, scaleID: "ionian")) {
        piece = Piece(title: title, tempoBPM: tempoBPM, key: key)
        currentPieceFilePath = nil
        append("New piece created: \(title)")
    }

    public func setSourceText(_ text: String) {
        sourceText = text
        append("Source text set (\(text.count) characters).")
    }

    private static let supportedLLMConnectionExtensions: Set<String> = ["json"]

    /// Scans `folderPath` for `.json` LLM connection descriptors — mirrors `listSampleFiles`.
    public func listLLMConnections(in folderPath: String) throws {
        let folderURL = URL(fileURLWithPath: folderPath)
        let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        llmConnectionsFolder = folderPath
        llmConnections = contents
            .filter { Self.supportedLLMConnectionExtensions.contains($0.pathExtension.lowercased()) }
            .map(\.lastPathComponent)
            .sorted()
        append(llmConnections.isEmpty
            ? "No .json LLM connection files found in \(folderPath)."
            : "Found \(llmConnections.count) LLM connection(s) in \(folderPath).")
    }

    public func useLLMConnection(named name: String) throws {
        guard let llmConnectionsFolder else { throw SessionError.noLLMConnectionsFolderListed }
        let url = URL(fileURLWithPath: llmConnectionsFolder).appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        let connection = try JSONDecoder().decode(LLMConnection.self, from: data)
        currentLLMConnection = connection
        append("Using LLM connection: \(connection.name) (\(connection.provider), model \(connection.model))")
    }

    /// Convenience over `useLLMConnection(named:)` using the 0-based position in `llmConnections`.
    public func useLLMConnection(atIndex index: Int) throws {
        guard llmConnections.indices.contains(index) else { throw SessionError.invalidLLMConnectionIndex }
        try useLLMConnection(named: llmConnections[index])
    }

    /// Sends `sourceText` to the selected LLM connection and, if the response survives
    /// theory-library validation (see `LLMPieceComposer`), replaces `piece` with the
    /// composed result. Any dropped/invalid parts of the response are logged as warnings
    /// either way — this never injects an unvalidated suggestion into the piece model.
    ///
    /// `generate` defaults to the real network call; tests pass a fake to exercise the
    /// parsing/validation/piece-assignment logic without hitting any actual LLM.
    public func composeFromText(generate: (String, LLMConnection) throws -> String = LLMClient.generate) throws {
        guard let sourceText else { throw SessionError.noSourceText }
        guard let connection = currentLLMConnection else { throw SessionError.noLLMConnectionSelected }

        append("Sending text to \(connection.name)...")
        let prompt = LLMPieceComposer.buildPrompt(sourceText: sourceText)
        let responseText = try generate(prompt, connection)

        let (composedPiece, warnings) = LLMPieceComposer.parseAndValidate(responseText: responseText)
        for warning in warnings { append("Compose warning: \(warning)") }
        guard let composedPiece else { throw SessionError.llmComposeFailed(warnings) }

        piece = composedPiece
        currentPieceFilePath = nil
        append("Composed '\(composedPiece.title)' from text (\(composedPiece.sections.count) section(s)).")
    }

    public func loadPiece(fromJSONFile path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try JSONDecoder().decode(Piece.self, from: data)
        piece = decoded
        currentPieceFilePath = path
        append("Loaded piece from \(path): \(decoded.title)")
    }

    public func savePiece(toJSONFile path: String) throws {
        guard let piece else { throw SessionError.noPieceLoaded }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(piece)
        try data.write(to: URL(fileURLWithPath: path))
        currentPieceFilePath = path
        append("Saved piece to \(path).")
    }

    private static let supportedPieceExtensions: Set<String> = ["json"]

    /// Scans `folderPath` for `.json` piece files and remembers both the folder and the
    /// match list (in `pieceFiles`) so they can be picked by index afterwards — mirrors
    /// `listSampleFiles`.
    public func listPieceFiles(in folderPath: String) throws {
        let folderURL = URL(fileURLWithPath: folderPath)
        let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        pieceFolder = folderPath
        pieceFiles = contents
            .filter { Self.supportedPieceExtensions.contains($0.pathExtension.lowercased()) }
            .map(\.lastPathComponent)
            .sorted()
        append(pieceFiles.isEmpty
            ? "No .json piece files found in \(folderPath)."
            : "Found \(pieceFiles.count) piece file(s) in \(folderPath).")
    }

    /// Loads a piece by name from the last-listed folder (see `listPieceFiles`).
    public func loadPiece(named name: String) throws {
        guard let pieceFolder else { throw SessionError.noPieceFolderListed }
        try loadPiece(fromJSONFile: URL(fileURLWithPath: pieceFolder).appendingPathComponent(name).path)
    }

    /// Convenience over `loadPiece(named:)` using the 0-based position in `pieceFiles`.
    public func loadPiece(atIndex index: Int) throws {
        guard pieceFiles.indices.contains(index) else { throw SessionError.invalidPieceIndex }
        try loadPiece(named: pieceFiles[index])
    }

    /// Re-saves the current piece to wherever it was last loaded from or saved to. Fails
    /// if that's never happened yet — use `savePiece(as:)` for a first save.
    public func savePiece() throws {
        guard let currentPieceFilePath else { throw SessionError.noCurrentPieceFile }
        try savePiece(toJSONFile: currentPieceFilePath)
    }

    /// Saves under a new name/path — "Save As". `nameOrPath` containing a "/" is used
    /// as-is (an explicit path); a bare name is resolved against `pieceFolder` (set via
    /// `listPieceFiles`). Adds a ".json" extension if missing either way.
    public func savePiece(as nameOrPath: String) throws {
        let resolvedPath: String
        if nameOrPath.contains("/") {
            resolvedPath = nameOrPath
        } else {
            guard let pieceFolder else { throw SessionError.noPieceFolderListed }
            resolvedPath = URL(fileURLWithPath: pieceFolder).appendingPathComponent(nameOrPath).path
        }
        try savePiece(toJSONFile: resolvedPath.hasSuffix(".json") ? resolvedPath : resolvedPath + ".json")
    }

    public func play() throws {
        guard let piece else { throw SessionError.noPieceLoaded }
        let notes = piece.renderedNotes()
        let timeline = piece.harmonicTimeline()
        let duration = PiecePlayer.totalDuration(of: notes)
        player.play(notes)

        playbackGeneration += 1
        let generation = playbackGeneration
        isPlaying = true
        playbackTimeline = timeline
        playbackCurrentChordIndex = timeline.isEmpty ? nil : 0
        playbackHeldPitches = []
        append("Playing '\(piece.title)': \(notes.count) notes, \(String(format: "%.1f", duration))s.")

        // Mirrors PiecePlayer's own note-on/off scheduling, but drives `playbackHeldPitches`
        // / `playbackCurrentChordIndex` (UI state) instead of the sampler (audio) — kept
        // separate from AudioEngine since this is presentation state, not sound. Scheduled
        // on `playbackStateQueue` (serial), not `.global()` (concurrent) — see that
        // property's doc comment for why.
        let now = DispatchTime.now()
        for note in notes {
            playbackStateQueue.asyncAfter(deadline: now + note.startSeconds) { [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                self.playbackHeldPitches.insert(note.pitch)
            }
            playbackStateQueue.asyncAfter(deadline: now + note.startSeconds + note.durationSeconds) { [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                self.playbackHeldPitches.remove(note.pitch)
            }
        }
        for (index, segment) in timeline.enumerated() {
            playbackStateQueue.asyncAfter(deadline: now + segment.startSeconds) { [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                self.playbackCurrentChordIndex = index
            }
        }

        // Same serial queue as above, not `.global()`/`.main` — a blocking-readLine REPL
        // never pumps the main run loop (a `.main` timer would simply never fire), and this
        // must not race the per-note/per-chord updates scheduled above.
        playbackStateQueue.asyncAfter(deadline: .now() + duration + 0.2) { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            self.isPlaying = false
            self.playbackHeldPitches = []
            self.playbackCurrentChordIndex = nil
            self.append("Playback finished.")
        }
    }

    public func availableMIDISources() -> [String] {
        MIDIInputListener.sourceNames()
    }

    /// Restricts `startListening` to a single MIDI source (0-based, matching
    /// `availableMIDISources()`'s order) instead of connecting to every one visible —
    /// useful once there's more than one (a physical keyboard alongside an unrelated
    /// virtual IAC bus, say) and only one of them should actually feed the app.
    public func useMIDISource(atIndex index: Int) throws {
        let sources = availableMIDISources()
        guard sources.indices.contains(index) else { throw SessionError.invalidMIDISourceIndex }
        selectedMIDISourceIndex = index
        append("Source MIDI selectionnee : \(sources[index])")
    }

    /// Reverts to the original "connect every visible source" behavior.
    public func useAllMIDISources() {
        selectedMIDISourceIndex = nil
        append("Source MIDI : toutes les sources visibles seront utilisees.")
    }

    private static let supportedSampleExtensions: Set<String> = ["sf2", "dls", "aupreset"]

    /// Scans `folderPath` for `.sf2`/`.dls`/`.aupreset` files and remembers both the folder
    /// and the match list (in `sampleFiles`) so they can be picked by index afterwards.
    public func listSampleFiles(in folderPath: String) throws {
        let folderURL = URL(fileURLWithPath: folderPath)
        let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        sampleFolder = folderPath
        sampleFiles = contents
            .filter { Self.supportedSampleExtensions.contains($0.pathExtension.lowercased()) }
            .map(\.lastPathComponent)
            .sorted()
        append(sampleFiles.isEmpty
            ? "No .sf2/.dls/.aupreset files found in \(folderPath)."
            : "Found \(sampleFiles.count) sample file(s) in \(folderPath).")
    }

    /// Loads a sample-based instrument by name from the last-listed folder (see
    /// `listSampleFiles`), replacing the sampler's current sound (the default sine synth,
    /// or whatever was loaded before).
    public func loadSample(named name: String) throws {
        guard let sampleFolder else { throw SessionError.noSampleFolderListed }
        let url = URL(fileURLWithPath: sampleFolder).appendingPathComponent(name)
        try player.loadSample(at: url)
        append("Loaded instrument: \(name)")
    }

    /// Convenience over `loadSample(named:)` using the 0-based position in `sampleFiles`.
    public func loadSample(atIndex index: Int) throws {
        guard sampleFiles.indices.contains(index) else { throw SessionError.invalidSampleIndex }
        try loadSample(named: sampleFiles[index])
    }

    /// Starts listening to every visible MIDI source. When `listenOnly` is true, incoming
    /// notes are logged but not sounded — for a physical keyboard that already makes its
    /// own sound, where the app only needs to see what's played (future recognition).
    public func startListening(listenOnly: Bool) throws {
        self.listenOnly = listenOnly
        let newListener = try MIDIInputListener { [weak self] event in
            self?.handleIncomingMIDIEvent(event)
        }
        if let selectedMIDISourceIndex {
            newListener.connectSource(atIndex: selectedMIDISourceIndex)
        } else {
            newListener.connectAllSources()
        }
        listener = newListener
        isListening = true
        append("Listening to MIDI (\(listenOnly ? "listen-only, no sound" : "sound through the app")).")
    }

    /// Simulates a key press/release without real MIDI hardware — useful for testing and
    /// demoing, and the same entry point a future on-screen/touch virtual keyboard would use.
    public func pressKey(pitch: Int, velocity: Int = 100, channel: Int = 0) {
        handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: pitch, velocity: velocity, channel: channel))
    }

    public func releaseKey(pitch: Int, channel: Int = 0) {
        handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOff, pitch: pitch, velocity: 0, channel: channel))
    }

    /// Everything that happens per incoming MIDI event: logging, feeding the recognizer,
    /// and (unless `listenOnly`) sounding the note. Extracted out of the `MIDIInputListener`
    /// closure so it's directly callable from tests without needing real CoreMIDI input.
    /// Runs on `liveInputQueue` (see its doc comment) so concurrent callers are serialized
    /// regardless of which thread each one happens to call in on; `.sync`, not `.async`, so
    /// existing callers that check state right after `pressKey`/`releaseKey` keep seeing it
    /// updated by the time the call returns.
    func handleIncomingMIDIEvent(_ event: MIDINoteEvent) {
        liveInputQueue.sync {
            lastMIDIEvent = event
            append("MIDI \(event.kind == .noteOn ? "on " : "off")pitch=\(event.pitch) vel=\(event.velocity) ch=\(event.channel)")

            switch event.kind {
            case .noteOn:
                recognizer.noteOn(pitch: event.pitch)
                heldPitches.insert(event.pitch)
            case .noteOff:
                recognizer.noteOff(pitch: event.pitch)
                heldPitches.remove(event.pitch)
            }
            refreshRecognition()

            guard !listenOnly else { return }
            switch event.kind {
            case .noteOn: player.startNote(pitch: event.pitch, velocity: event.velocity, channel: event.channel)
            case .noteOff: player.stopNote(pitch: event.pitch, channel: event.channel)
            }
        }
    }

    public func stopListening() {
        guard isListening else { return }
        listener = nil
        isListening = false
        // Same queue as `handleIncomingMIDIEvent`: this touches the same `recognizer`/
        // `heldPitches` state, so it needs the same protection against a still-pending
        // `keyboard-source` release timer firing concurrently with this reset.
        liveInputQueue.sync {
            recognizer.reset()
            recognizedChord = nil
            recognizedModes = []
            heldPitches = []
            append("Stopped listening to MIDI.")
        }
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

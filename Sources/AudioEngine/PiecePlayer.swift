@preconcurrency import AVFoundation
import PieceModel

public enum SampleLoadError: Error, CustomStringConvertible {
    case unsupportedExtension(String)

    public var description: String {
        switch self {
        case .unsupportedExtension(let ext):
            return "unsupported sample file extension \".\(ext)\" (expected .sf2, .dls or .aupreset)"
        }
    }
}

/// Non-realtime playback of a rendered `Piece`: schedules every note against an
/// `AVAudioUnitSampler` (Apple's built-in sine synth by default, or a loaded sample-based
/// instrument via `loadSample`). A note with a non-nil `RenderedNote.instrumentName` sounds
/// through its own dedicated `SamplerUnit` instead (created lazily, one per distinct name
/// seen across calls to `play(_:instrumentURLs:)`) — the same "several independent
/// AVAudioEngine/AVAudioUnitSampler instances sounding at once" pattern already proven for
/// live-input tracks, reused here so a piece's chords and each melodic line/track can carry
/// a genuinely different timbre. Not thread-safe beyond calling `start()` once before any
/// `play(_:)`.
/// `@unchecked Sendable`: `playGeneration`/`activePitchesByInstrument` (the only mutable state
/// touched from more than one thread — `namedSamplers`/`engine`/`sampler` are only ever
/// touched from whichever thread calls `play(_:)`/`loadSample`) are guarded by `stateLock`.
public final class PiecePlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var namedSamplers: [String: SamplerUnit] = [:]

    // Guards `playGeneration`/`activePitchesByInstrument` below — both are read/written from
    // this player's own `DispatchQueue.global()`-scheduled note-on/off closures (several,
    // concurrently) as well as from whichever thread calls `play(_:)`/`stopAllNotes()` (the
    // UI thread) — the same "plain Swift state touched from more than one thread" pattern
    // that has caused real crashes elsewhere in this project (see `ImprovSession`'s own
    // `playbackStateQueue`), so this needs real synchronization, not just a comment.
    private let stateLock = NSLock()
    private var playGeneration = 0
    private var activePitchesByInstrument: [String?: Set<Int>] = [:]

    public init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
    }

    public func start() throws {
        PlaybackAudioSession.activateIfNeeded()
        try engine.start()
    }

    public func stop() {
        engine.stop()
    }

    /// Schedules every note in `notes` relative to "now" and returns immediately. The
    /// caller must keep the process alive for at least `Self.totalDuration(of: notes)`
    /// seconds for playback to be heard in full. `instrumentURLs` maps every distinct
    /// `RenderedNote.instrumentName` that should sound differently from the default to a
    /// sample file to load onto its own `SamplerUnit`; a name with no entry (folder not
    /// resolved, file missing) falls back to that unit's default sound rather than failing
    /// the whole call — same "drop what's invalid, warn, keep going" convention used
    /// elsewhere in this app. Returns any such warnings (empty when everything resolved).
    @discardableResult
    public func play(_ notes: [RenderedNote], instrumentURLs: [String: URL] = [:]) -> [String] {
        var warnings: [String] = []
        // Re-resolved on every call (not "load once, cache forever") so a name that
        // couldn't be found on an earlier play (e.g. the sample folder wasn't listed yet)
        // gets a real chance to load next time, rather than being stuck with the default
        // sound for this `PiecePlayer`'s whole lifetime.
        for name in Set(notes.compactMap(\.instrumentName)) {
            let unit: SamplerUnit
            if let existing = namedSamplers[name] {
                unit = existing
            } else {
                unit = SamplerUnit()
                do {
                    try unit.start()
                } catch {
                    warnings.append("instrument '\(name)': impossible de demarrer son moteur audio (\(error)) — son par defaut utilise")
                    namedSamplers[name] = unit
                    continue
                }
                namedSamplers[name] = unit
            }
            if let url = instrumentURLs[name] {
                do {
                    try unit.loadSample(at: url)
                } catch {
                    warnings.append("instrument '\(name)': impossible de charger \(url.lastPathComponent) (\(error)) — son par defaut utilise")
                }
            } else {
                warnings.append("instrument '\(name)' introuvable — son par defaut utilise")
            }
        }

        stateLock.lock()
        playGeneration += 1
        let generation = playGeneration
        stateLock.unlock()

        let now = DispatchTime.now()
        for note in notes {
            let target = note.instrumentName.flatMap { namedSamplers[$0] }
            DispatchQueue.global().asyncAfter(deadline: now + note.startSeconds) { [weak self, sampler] in
                guard let self, self.isCurrentGeneration(generation) else { return }
                if let target {
                    target.startNote(pitch: note.pitch, velocity: note.velocity)
                } else {
                    sampler.startNote(Self.clampedByte(note.pitch), withVelocity: Self.clampedByte(note.velocity), onChannel: 0)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: now + note.startSeconds + note.durationSeconds) { [weak self, sampler] in
                guard let self, self.isCurrentGeneration(generation) else { return }
                if let target {
                    target.stopNote(pitch: note.pitch)
                } else {
                    sampler.stopNote(Self.clampedByte(note.pitch), onChannel: 0)
                }
            }
        }
        // Safety net: when two parts share a pitch class (common — see the demo piece's G7
        // measure), two overlapping note-ons for the same key can leave a sampler voice
        // retriggered by one part while the other part's own note-off (scheduled for its
        // own, earlier end time) is the one that actually reaches the sampler — the
        // later-ending part's note-off then targets a voice that already considers itself
        // off, and the key is left audibly stuck. Force every pitch used by each target off
        // once, right after the piece's true last note-off should have fired, so nothing is
        // ever left ringing regardless of which overlap caused it. Grouped per instrument
        // name (not one global set) since each name sounds through its own sampler — also
        // remembered in `activePitchesByInstrument` so `stopAllNotes()` (an early "Arreter"
        // button press, not just this natural end-of-piece cleanup) knows what to silence.
        let totalDuration = Self.totalDuration(of: notes)
        var pitchesByInstrument: [String?: Set<Int>] = [:]
        for note in notes {
            pitchesByInstrument[note.instrumentName, default: []].insert(note.pitch)
        }
        stateLock.lock()
        activePitchesByInstrument = pitchesByInstrument
        stateLock.unlock()
        for (name, pitches) in pitchesByInstrument {
            let target = name.flatMap { namedSamplers[$0] }
            DispatchQueue.global().asyncAfter(deadline: now + totalDuration + 0.05) { [weak self, sampler] in
                guard let self, self.isCurrentGeneration(generation) else { return }
                for pitch in pitches {
                    if let target {
                        target.stopNote(pitch: pitch)
                    } else {
                        sampler.stopNote(Self.clampedByte(pitch), onChannel: 0)
                    }
                }
                self.clearActivePitches(ifStillGeneration: generation)
            }
        }
        return warnings
    }

    private func isCurrentGeneration(_ generation: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return playGeneration == generation
    }

    private func clearActivePitches(ifStillGeneration generation: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard playGeneration == generation else { return }
        activePitchesByInstrument = [:]
    }

    /// Immediately silences every note this player might currently have sounding (from the
    /// most recent `play(_:)` call), and invalidates that call's still-pending scheduled
    /// note-on/note-off closures so they become no-ops instead of firing later — the
    /// "Arreter" button's counterpart to letting a piece finish on its own.
    public func stopAllNotes() {
        stateLock.lock()
        playGeneration += 1
        let pitchesByInstrument = activePitchesByInstrument
        activePitchesByInstrument = [:]
        stateLock.unlock()
        for (name, pitches) in pitchesByInstrument {
            let target = name.flatMap { namedSamplers[$0] }
            for pitch in pitches {
                if let target {
                    target.stopNote(pitch: pitch)
                } else {
                    sampler.stopNote(Self.clampedByte(pitch), onChannel: 0)
                }
            }
        }
    }

    /// Triggers a note immediately — the realtime counterpart to `play(_:)`, for live
    /// input (e.g. a physical MIDI keyboard) rather than a pre-authored `Piece`.
    public func startNote(pitch: Int, velocity: Int, channel: Int = 0) {
        sampler.startNote(Self.clampedByte(pitch), withVelocity: Self.clampedByte(velocity), onChannel: Self.clampedByte(channel))
    }

    public func stopNote(pitch: Int, channel: Int = 0) {
        sampler.stopNote(Self.clampedByte(pitch), onChannel: Self.clampedByte(channel))
    }

    /// Swaps the sampler's sound for a sample-based instrument loaded from disk: a
    /// SoundFont/DLS bank (`.sf2`/`.dls`, program 0 = first instrument in the bank) or an
    /// Apple `.aupreset`. Replaces whatever was previously loaded (or the default sine synth).
    public func loadSample(at url: URL, program: UInt8 = 0) throws {
        switch url.pathExtension.lowercased() {
        case "sf2", "dls":
            try sampler.loadSoundBankInstrument(
                at: url,
                program: program,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
        case "aupreset":
            try sampler.loadInstrument(at: url)
        default:
            throw SampleLoadError.unsupportedExtension(url.pathExtension)
        }
    }

    public static func totalDuration(of notes: [RenderedNote]) -> Double {
        notes.map { $0.startSeconds + $0.durationSeconds }.max() ?? 0
    }

    private static func clampedByte(_ value: Int) -> UInt8 {
        UInt8(clamping: max(0, min(127, value)))
    }
}

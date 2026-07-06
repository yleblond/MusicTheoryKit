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
/// instrument via `loadSample`). Not thread-safe beyond calling `start()` once before any
/// `play(_:)`.
public final class PiecePlayer {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()

    public init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
    }

    public func start() throws {
        try engine.start()
    }

    public func stop() {
        engine.stop()
    }

    /// Schedules every note in `notes` relative to "now" and returns immediately.
    /// The caller must keep the process alive for at least `Self.totalDuration(of: notes)`
    /// seconds for playback to be heard in full.
    public func play(_ notes: [RenderedNote]) {
        let now = DispatchTime.now()
        for note in notes {
            DispatchQueue.global().asyncAfter(deadline: now + note.startSeconds) { [sampler] in
                sampler.startNote(Self.clampedByte(note.pitch), withVelocity: Self.clampedByte(note.velocity), onChannel: 0)
            }
            DispatchQueue.global().asyncAfter(deadline: now + note.startSeconds + note.durationSeconds) { [sampler] in
                sampler.stopNote(Self.clampedByte(note.pitch), onChannel: 0)
            }
        }
        // Safety net: when a chord and a melody share a pitch class (common — see the demo
        // piece's G7 measure), two overlapping note-ons for the same key can leave the
        // sampler's voice for that pitch retriggered by one part while the other part's own
        // note-off (scheduled for its own, earlier end time) is the one that actually reaches
        // the sampler — the later-ending part's note-off then targets a voice that already
        // considers itself off, and the key is left audibly stuck. Force every pitch used in
        // this piece off once, right after the piece's true last note-off should have fired,
        // so nothing is ever left ringing regardless of which overlap caused it.
        let totalDuration = Self.totalDuration(of: notes)
        let uniquePitches = Set(notes.map(\.pitch))
        DispatchQueue.global().asyncAfter(deadline: now + totalDuration + 0.05) { [sampler] in
            for pitch in uniquePitches {
                sampler.stopNote(Self.clampedByte(pitch), onChannel: 0)
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

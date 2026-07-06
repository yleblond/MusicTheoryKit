@preconcurrency import AVFoundation
import PieceModel

/// Non-realtime playback of a rendered `Piece`: schedules every note against an
/// `AVAudioUnitSampler` (Apple's built-in sine synth when no sound bank is loaded).
/// Not thread-safe beyond calling `start()` once before any `play(_:)`.
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
    }

    /// Triggers a note immediately — the realtime counterpart to `play(_:)`, for live
    /// input (e.g. a physical MIDI keyboard) rather than a pre-authored `Piece`.
    public func startNote(pitch: Int, velocity: Int, channel: Int = 0) {
        sampler.startNote(Self.clampedByte(pitch), withVelocity: Self.clampedByte(velocity), onChannel: Self.clampedByte(channel))
    }

    public func stopNote(pitch: Int, channel: Int = 0) {
        sampler.stopNote(Self.clampedByte(pitch), onChannel: Self.clampedByte(channel))
    }

    public static func totalDuration(of notes: [RenderedNote]) -> Double {
        notes.map { $0.startSeconds + $0.durationSeconds }.max() ?? 0
    }

    private static func clampedByte(_ value: Int) -> UInt8 {
        UInt8(clamping: max(0, min(127, value)))
    }
}

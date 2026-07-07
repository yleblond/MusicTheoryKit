@preconcurrency import AVFoundation
import SoundTrackModel

/// Non-realtime playback of a `SoundTrack` — the temporal-recording counterpart to
/// `PiecePlayer`. Simpler than `PiecePlayer` in one way (`RecordedNoteEvent.timeSeconds` is
/// already an absolute offset, no beats-to-seconds conversion needed) and in another way
/// not a variant of it at all: this replays the *exact* raw on/off event stream as recorded
/// — every overlap, every real-world timing quirk — rather than reconstructing note+duration
/// pairs from a measure-based model.
public final class SoundTrackPlayer {
    private let sampler = SamplerUnit()

    public init() {}

    public func start() throws {
        try sampler.start()
    }

    public func stop() {
        sampler.stop()
    }

    /// Schedules every event in `soundTrack` relative to "now" and returns immediately —
    /// same calling convention as `PiecePlayer.play(_:)`. All tracks that contributed to the
    /// recording sound through this one sampler (no per-original-track timbre in this first
    /// version — see `SoundTrack.trackIDs` if a future version wants to split them out).
    public func play(_ soundTrack: SoundTrack) {
        let now = DispatchTime.now()
        for event in soundTrack.events {
            DispatchQueue.global().asyncAfter(deadline: now + event.timeSeconds) { [sampler] in
                if event.isNoteOn {
                    sampler.startNote(pitch: event.pitch, velocity: event.velocity)
                } else {
                    sampler.stopNote(pitch: event.pitch)
                }
            }
        }
        // Same stuck-note safety net as `PiecePlayer.play(_:)`, for the same reason: two
        // overlapping notes on the same pitch (two tracks recorded together, say) can leave
        // a voice's note-off targeting a voice that another track's note-on already
        // retriggered. Force every pitch used in this recording off once, right after the
        // recording's own last event should have fired.
        let uniquePitches = Set(soundTrack.events.map(\.pitch))
        DispatchQueue.global().asyncAfter(deadline: now + soundTrack.durationSeconds + 0.05) { [sampler] in
            for pitch in uniquePitches {
                sampler.stopNote(pitch: pitch)
            }
        }
    }
}

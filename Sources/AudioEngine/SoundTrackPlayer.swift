@preconcurrency import AVFoundation
import SoundFontModel
import SoundTrackModel

/// Non-realtime playback of a `SoundTrack` — the temporal-recording counterpart to
/// `PiecePlayer`. Simpler than `PiecePlayer` in one way (`RecordedNoteEvent.timeSeconds` is
/// already an absolute offset, no beats-to-seconds conversion needed) and in another way
/// not a variant of it at all: this replays the *exact* raw on/off event stream as recorded
/// — every overlap, every real-world timing quirk — rather than reconstructing note+duration
/// pairs from a measure-based model.
/// `@unchecked Sendable`: `playGeneration`/`activePitches` (the only mutable state touched
/// from more than one thread) are guarded by `stateLock`.
public final class SoundTrackPlayer: @unchecked Sendable {
    private let sampler = SamplerUnit()

    // Guards `playGeneration`/`activePitches` below — read/written from several concurrent
    // `DispatchQueue.global()`-scheduled closures as well as from whichever thread calls
    // `play(_:)`/`stopAllNotes()` (the UI thread) — same reasoning as `PiecePlayer`'s own
    // `stateLock`.
    private let stateLock = NSLock()
    private var playGeneration = 0
    private var activePitches: Set<Int> = []

    public init() {}

    public func start() throws {
        try sampler.start()
    }

    public func stop() {
        sampler.stop()
    }

    /// Swaps this player's own sound for a sample-based instrument — separate from
    /// `PiecePlayer`'s own default sampler, since a `SoundTrack` recording and a `Piece`
    /// play through entirely different `AVAudioUnitSampler`s. `nil`/never called means the
    /// default sine synth, same "no explicit choice = the built-in default" convention
    /// `PiecePlayer.loadSample` already uses.
    public func loadSample(at url: URL, preset: SoundFontPresetIdentity? = nil) throws {
        try sampler.loadSample(at: url, preset: preset)
    }

    /// Schedules every event in `soundTrack` relative to "now" and returns immediately —
    /// same calling convention as `PiecePlayer.play(_:)`. All tracks that contributed to the
    /// recording sound through this one sampler (no per-original-track timbre in this first
    /// version — see `SoundTrack.trackIDs` if a future version wants to split them out).
    public func play(_ soundTrack: SoundTrack) {
        stateLock.lock()
        playGeneration += 1
        let generation = playGeneration
        activePitches = Set(soundTrack.events.map(\.pitch))
        stateLock.unlock()

        let now = DispatchTime.now()
        for event in soundTrack.events {
            DispatchQueue.global().asyncAfter(deadline: now + event.timeSeconds) { [weak self, sampler] in
                guard let self, self.isCurrentGeneration(generation) else { return }
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
        DispatchQueue.global().asyncAfter(deadline: now + soundTrack.durationSeconds + 0.05) { [weak self, sampler] in
            guard let self, self.isCurrentGeneration(generation) else { return }
            let pitches = self.clearActivePitches(ifStillGeneration: generation)
            for pitch in pitches { sampler.stopNote(pitch: pitch) }
        }
    }

    private func isCurrentGeneration(_ generation: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return playGeneration == generation
    }

    @discardableResult
    private func clearActivePitches(ifStillGeneration generation: Int) -> Set<Int> {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard playGeneration == generation else { return [] }
        let pitches = activePitches
        activePitches = []
        return pitches
    }

    /// Immediately silences every note from the most recent `play(_:)` call, and invalidates
    /// its still-pending scheduled events so they become no-ops instead of firing later —
    /// the "Arreter" button's counterpart to letting a recording finish on its own.
    public func stopAllNotes() {
        stateLock.lock()
        playGeneration += 1
        let pitches = activePitches
        activePitches = []
        stateLock.unlock()
        for pitch in pitches { sampler.stopNote(pitch: pitch) }
    }
}

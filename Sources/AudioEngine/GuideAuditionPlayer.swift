import Foundation

/// One chord (or single note) to hold for `durationSeconds` starting `startSeconds` after
/// audition playback begins — not shaped like `RenderedNote` (per-pitch note events from a
/// measured `Piece`): a `GuideSequence` has no melody or beats, just an ordered list of held
/// pitch-class groups, so the caller (`ImprovSession`) resolves each step's chords into these
/// flat chord-shaped groups before handing them to this player.
public struct GuideAuditionChord: Sendable {
    public let pitches: [Int]
    public let startSeconds: Double
    public let durationSeconds: Double

    public init(pitches: [Int], startSeconds: Double, durationSeconds: Double) {
        self.pitches = pitches
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
    }
}

/// Non-realtime "listen to this guide" playback — same shape as `SoundTrackPlayer` (a
/// self-contained scheduler over its own dedicated `SamplerUnit`, plus a stuck-note safety net),
/// deliberately not shared with it or `PiecePlayer`: a guide audition is neither a measured
/// `Piece` nor a raw recorded event stream, just a flat sequence of chord-holds.
/// `@unchecked Sendable`: `playGeneration`/`activePitches` (the only mutable state touched from
/// more than one thread) are guarded by `stateLock`, same reasoning as `SoundTrackPlayer`.
public final class GuideAuditionPlayer: @unchecked Sendable {
    private let sampler = SamplerUnit()

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

    /// Same three formats `PiecePlayer.loadSample`/`SoundTrackPlayer.loadSample` support —
    /// this player's own dedicated sampler, independent of every other one in the app.
    public func loadSample(at url: URL, program: UInt8 = 0) throws {
        try sampler.loadSample(at: url, program: program)
    }

    /// Schedules every chord relative to "now" and returns immediately — same calling
    /// convention as `SoundTrackPlayer.play(_:)`.
    public func play(_ chords: [GuideAuditionChord]) {
        stateLock.lock()
        playGeneration += 1
        let generation = playGeneration
        activePitches = Set(chords.flatMap(\.pitches))
        stateLock.unlock()

        let now = DispatchTime.now()
        for chord in chords {
            DispatchQueue.global().asyncAfter(deadline: now + chord.startSeconds) { [weak self, sampler] in
                guard let self, self.isCurrentGeneration(generation) else { return }
                for pitch in chord.pitches { sampler.startNote(pitch: pitch, velocity: 90) }
            }
            DispatchQueue.global().asyncAfter(deadline: now + chord.startSeconds + chord.durationSeconds) { [weak self, sampler] in
                guard let self, self.isCurrentGeneration(generation) else { return }
                for pitch in chord.pitches { sampler.stopNote(pitch: pitch) }
            }
        }
        // Same stuck-note safety net as `SoundTrackPlayer.play(_:)`: force every pitch used in
        // this audition off once, right after its own last event should have fired.
        let totalDuration = chords.map { $0.startSeconds + $0.durationSeconds }.max() ?? 0
        DispatchQueue.global().asyncAfter(deadline: now + totalDuration + 0.05) { [weak self, sampler] in
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
    /// its still-pending scheduled events so they become no-ops instead of firing later.
    public func stopAllNotes() {
        stateLock.lock()
        playGeneration += 1
        let pitches = activePitches
        activePitches = []
        stateLock.unlock()
        for pitch in pitches { sampler.stopNote(pitch: pitch) }
    }
}

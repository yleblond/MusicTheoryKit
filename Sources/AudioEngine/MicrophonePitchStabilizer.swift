/// One note-on/off transition emitted by `MicrophonePitchStabilizer.ingest(_:)` once it has
/// been "confirmed" per that stabilizer's `Policy` — see that type's doc comment.
public struct StabilizedTransition: Equatable, Sendable {
    public enum Kind: Sendable, Equatable { case noteOn, noteOff }
    public let pitch: Int
    public let kind: Kind

    public init(pitch: Int, kind: Kind) {
        self.pitch = pitch
        self.kind = kind
    }
}

/// Turns a stream of raw per-analysis-window MIDI pitch sets (as reported every ~93ms by
/// `MicrophonePitchListener`) into debounced note-on/note-off transitions, damping the
/// frame-to-frame flicker a polyphonic microphone signal can show between a note's true
/// fundamental and a momentarily-louder harmonic. Pure state machine — no FFT/audio/session
/// dependency — so it's directly unit-testable against synthetic pitch-set sequences, and
/// (by design) not internally synchronized: every call must come from the same serial queue
/// the caller already uses for live-input state (this project's one hard concurrency rule is
/// to never give live-input state a second, independent lock/queue).
///
/// Two confirmation policies are implemented side by side, deliberately, so they can be
/// compared against real playing rather than committing to one up front: `.latched(windows:)`
/// requires `windows` *consecutive* agreeing analysis windows before confirming a change;
/// `.sliding(windows:)` confirms by simple majority over the last (up to) `windows` windows,
/// tolerating one dropped/aliased window without losing confirmation. `.passthrough` (used for
/// the two monophonic recognition modes, whose fix is spectral, not temporal — see
/// `FFTPitchAnalyzer.monophonicFundamentalHeuristic`/`monophonicFundamentalHPS`) confirms every
/// window immediately, matching this app's original unsmoothed microphone behavior — this is
/// also what `.latched(windows: 1)`/`.sliding(windows: 1)` degenerate to, a built-in regression
/// anchor.
public final class MicrophonePitchStabilizer {
    public enum Policy: Sendable, Equatable {
        case passthrough
        case latched(windows: Int)
        case sliding(windows: Int)
    }

    private let policy: Policy
    private let windowDepth: Int
    private var history: [Int: [Bool]] = [:]
    public private(set) var confirmedPitches: Set<Int> = []

    public init(policy: Policy) {
        self.policy = policy
        switch policy {
        case .passthrough: windowDepth = 1
        case .latched(let windows): windowDepth = max(1, windows)
        case .sliding(let windows): windowDepth = max(1, windows)
        }
    }

    /// Feeds one analysis window's raw detected pitch set; returns the transitions (every
    /// note-off before any note-on, each group sorted by pitch for deterministic ordering)
    /// that just became confirmed as a result, if any. `confirmedPitches` reflects the state
    /// *after* this call.
    public func ingest(_ rawPitches: Set<Int>) -> [StabilizedTransition] {
        if case .passthrough = policy {
            let dropped = confirmedPitches.subtracting(rawPitches).sorted()
            let added = rawPitches.subtracting(confirmedPitches).sorted()
            confirmedPitches = rawPitches
            return dropped.map { StabilizedTransition(pitch: $0, kind: .noteOff) }
                + added.map { StabilizedTransition(pitch: $0, kind: .noteOn) }
        }

        let trackedPitches = confirmedPitches.union(rawPitches).union(history.keys)
        var confirmedOns: [Int] = []
        var confirmedOffs: [Int] = []

        for pitch in trackedPitches {
            var samples = history[pitch] ?? []
            samples.append(rawPitches.contains(pitch))
            if samples.count > windowDepth { samples.removeFirst(samples.count - windowDepth) }
            history[pitch] = samples

            let isConfirmed = confirmedPitches.contains(pitch)
            let presentCount = samples.filter { $0 }.count
            let shouldConfirmOn: Bool
            let shouldConfirmOff: Bool
            switch policy {
            case .passthrough:
                shouldConfirmOn = false
                shouldConfirmOff = false
            case .latched:
                shouldConfirmOn = samples.count == windowDepth && presentCount == windowDepth
                shouldConfirmOff = samples.count == windowDepth && presentCount == 0
            case .sliding:
                // Only evaluate once the window is actually full — otherwise a single
                // just-appeared pitch would trivially be "100% of 1 sample", confirming
                // instantly with no smoothing at all on the way in (only on the way out),
                // defeating the point of a sliding window.
                shouldConfirmOn = samples.count == windowDepth && presentCount * 2 > samples.count
                shouldConfirmOff = samples.count == windowDepth && (samples.count - presentCount) * 2 > samples.count
            }

            if !isConfirmed, shouldConfirmOn {
                confirmedPitches.insert(pitch)
                confirmedOns.append(pitch)
            } else if isConfirmed, shouldConfirmOff {
                confirmedPitches.remove(pitch)
                confirmedOffs.append(pitch)
            }

            // An unconfirmed pitch with an all-absent history carries no information worth
            // keeping — bounds memory for pitches that briefly flickered and never confirmed.
            if !confirmedPitches.contains(pitch), presentCount == 0 {
                history[pitch] = nil
            }
        }

        return confirmedOffs.sorted().map { StabilizedTransition(pitch: $0, kind: .noteOff) }
            + confirmedOns.sorted().map { StabilizedTransition(pitch: $0, kind: .noteOn) }
    }

    /// Clears all history and confirmed state — call when the track stops listening or its
    /// mode changes, so a new listen session never inherits stale debounce state.
    public func reset() {
        history.removeAll()
        confirmedPitches.removeAll()
    }
}

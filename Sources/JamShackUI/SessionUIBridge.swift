import Foundation
import AppCore

/// Bridges a live `ImprovSession` to SwiftUI. Deliberately does NOT bind SwiftUI views
/// directly to `session.tracks`/`session.isPlaying`/etc.: those are mutated from background
/// threads (MIDI/microphone/network callbacks) via `ImprovSession`'s internal
/// `liveInputQueue`/`playbackStateQueue`, with no corresponding synchronization on the read
/// side for an external caller — exactly the pattern that has already caused real crashes in
/// this project (see Docs/BACKLOG.md), and confirmed still present by a Thread Sanitizer run
/// of `ImprovSessionConcurrencyStressTests` (a benign read/write race on `isPlaying`/
/// `playbackHeldPitches`, distinct from the three already-fixed write/write races).
///
/// Instead, this polls `session.buildWebConsoleState()` — the one function in the codebase
/// that already takes its own `.sync` on both queues and returns a fully-resolved, plain
/// value snapshot (`WebConsoleState`) — the exact same technique the web console's own
/// `/state` endpoint already relies on, just in-process and faster (~30Hz vs. the web
/// console's 4Hz HTTP poll) since no JSON round trip is needed.
@MainActor
@Observable
public final class SessionUIBridge {
    public private(set) var state: WebConsoleState
    private var pollTask: Task<Void, Never>?

    public init(session: ImprovSession, pollsPerSecond: Double = 30) {
        state = session.buildWebConsoleState()
        let interval = Duration.seconds(1.0 / pollsPerSecond)
        // No explicit cancellation on deinit: `deinit` runs nonisolated and can't touch
        // main-actor state synchronously. Not needed anyway — once `self` is deallocated,
        // the weak capture below goes nil and this loop exits on its own next iteration.
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let next = await Task.detached { session.buildWebConsoleState() }.value
                if Task.isCancelled { return }
                self.state = next
                try? await Task.sleep(for: interval)
            }
        }
    }
}

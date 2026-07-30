import Foundation
import AppCore
import SoundFontModel

/// Owns the "try a sound on a live track" state/logic shared by `SoundLibraryView` and
/// `FavoriteSoundsView` — a single instance, created once by the top-level `SoundsView` and
/// passed to both tabs, so switching between "Bibliotheque"/"Favoris" never interrupts an
/// active test (the source keeps playing, the keyboard visualization keeps updating) instead of
/// each tab owning its own independent, and inevitably conflicting, copy of this state.
// `@unchecked Sendable`: same rationale as `ImprovSession`/`SoundFontLibrary` — mutated only via
// SwiftUI (effectively the main thread), captured into `Task`/`Task.detached` for the real disk
// I/O `setInstrument` does, never touched concurrently in practice.
@Observable
final class SoundTestModeController: @unchecked Sendable {
    let session: ImprovSession

    private(set) var isTestModeOn = false
    private(set) var testSourceID: TrackID?
    private(set) var isChangingTestSource = false
    /// `"<hash>|<presetID>"` of the sound row currently loading via `testSound`, `nil`
    /// otherwise — also doubles as a simple lock against starting a second concurrent test.
    private(set) var testingSoundKey: String?
    var actionError: String?

    /// Whether `testSourceID` was already listening BEFORE test mode picked it — so leaving
    /// test mode restores it to that same state instead of unconditionally stopping it (it
    /// might be the computer keyboard's always-on startup track, for instance).
    private var testSourceWasAlreadyListening = false
    /// Every other track that WAS listening when a test source was chosen — paused for the
    /// duration of the test and restarted once test mode ends or the source changes.
    private var pausedTrackIDs: Set<TrackID> = []
    /// The test source's own instrument, exactly as it was BEFORE testing touched it — restored
    /// on every source switch/test-mode exit so browsing sounds here can never permanently
    /// override what the active scene actually defines for that track.
    private var testSourceOriginalInstrumentName: String?
    private var testSourceOriginalInstrumentPreset: SoundFontPresetIdentity?
    private var testSourceOriginalSoundEnabled = false
    /// Whether `ImprovSession.computerKeyboardInputEnabled` was already on before test mode
    /// turned it on — so leaving restores it to that same state instead of unconditionally
    /// turning it back off.
    private var computerKeyboardWasEnabledBeforeTestMode = false

    init(session: ImprovSession) {
        self.session = session
    }

    /// Local, sound-capable tracks only — the same "clavier ordinateur / MIDI" choices the rest
    /// of the app already exposes as live-input sources. Excludes `.microphone` (can never have
    /// sound, feedback risk) and `.webKeyboard`/`.remote` (not something to attach a local
    /// sample to for a quick test).
    var testableSources: [TrackInfo] {
        session.tracks.filter { track in
            switch track.id {
            case .computerKeyboard, .midiMerged, .midiSource: return true
            default: return false
            }
        }
    }

    /// The test source's own track — read directly rather than cached separately, so
    /// `currentlyTestedHash`/`currentlyTestedPreset` can never drift from what's actually
    /// loaded (both `instrumentName`/`instrumentPreset` are only ever set by `setInstrument`).
    private var testTrack: TrackInfo? {
        guard let testSourceID else { return nil }
        return session.tracks.first { $0.id == testSourceID }
    }

    /// `setInstrument` stores whatever absolute path was loaded — resolve it back to a hash by
    /// matching the index, so callers can key their "currently playing" badge off the same hash
    /// they already use everywhere else, instead of carrying a second, path-based identity.
    var currentlyTestedHash: String? {
        guard let path = testTrack?.instrumentName else { return nil }
        return session.soundFonts.first { session.soundFontPath(forHash: $0.hash) == path }?.hash
    }
    var currentlyTestedPreset: SoundFontPresetIdentity? { testTrack?.instrumentPreset }

    /// Idempotent (a repeated call with the same value is a no-op) — callers can call this
    /// unconditionally on appear/disappear without tracking whether it already ran.
    func setTestMode(_ enabled: Bool) {
        guard enabled != isTestModeOn else { return }
        isTestModeOn = enabled
        if enabled {
            computerKeyboardWasEnabledBeforeTestMode = session.computerKeyboardInputEnabled
            if !session.computerKeyboardInputEnabled {
                session.setComputerKeyboardInputEnabled(true)
            }
            // Computer keyboard as the default test source, per explicit user request — it's
            // also what makes the persistent keyboard bar appear (see `ContentView`).
            applyTestSource(.computerKeyboard)
        } else {
            applyTestSource(nil)
            if !computerKeyboardWasEnabledBeforeTestMode {
                session.setComputerKeyboardInputEnabled(false)
            }
        }
    }

    /// The one place `testSourceID` ever changes: restores the PREVIOUS source's own original
    /// sound and whatever else was listening, then — if a new source was picked — snapshots ITS
    /// current sound so it can be restored the same way later, pauses every other
    /// currently-listening track, and starts/enables the new one. Symmetric handling of `nil`
    /// (test mode's own "Aucune" choice, and turning test mode off) is what makes leaving the
    /// sound list exactly as it was found always safe, not just on the common "toggle off" path.
    /// Restoring the previous test source's own instrument can load a sample-based instrument
    /// via `setInstrument` — real disk I/O, so that step runs off the main thread
    /// (`Task.detached`).
    func applyTestSource(_ newSource: TrackID?) {
        isChangingTestSource = true
        let session = self.session
        Task {
            defer { isChangingTestSource = false }
            if let previous = testSourceID {
                if !testSourceWasAlreadyListening {
                    session.stopTrack(previous)
                }
                let originalName = testSourceOriginalInstrumentName
                let originalPreset = testSourceOriginalInstrumentPreset
                let originalSoundEnabled = testSourceOriginalSoundEnabled
                await Task.detached {
                    if let originalName {
                        try? session.setInstrument(named: originalName, for: previous, preset: originalPreset)
                    }
                    try? session.setSoundEnabled(originalSoundEnabled, for: previous)
                }.value
            }
            for id in pausedTrackIDs {
                do {
                    try session.startTrack(id)
                } catch {
                    actionError = "\(error)"
                }
            }
            pausedTrackIDs = []
            testSourceWasAlreadyListening = false
            testSourceID = newSource
            // The Picker used to reach `newSource` is a native pop-up control that otherwise
            // keeps SwiftUI keyboard focus for the rest of the session — see
            // `ImprovSession.requestComputerKeyboardFocus`'s own doc comment.
            session.requestComputerKeyboardFocus()

            guard let newSource else {
                testSourceOriginalInstrumentName = nil
                testSourceOriginalInstrumentPreset = nil
                testSourceOriginalSoundEnabled = false
                return
            }
            let newTrack = session.tracks.first { $0.id == newSource }
            testSourceOriginalInstrumentName = newTrack?.instrumentName
            testSourceOriginalInstrumentPreset = newTrack?.instrumentPreset
            testSourceOriginalSoundEnabled = newTrack?.soundEnabled ?? false
            testSourceWasAlreadyListening = newTrack?.isListening ?? false
            pausedTrackIDs = Set(session.tracks.filter { $0.isListening && $0.id != newSource }.map(\.id))
            for id in pausedTrackIDs {
                session.stopTrack(id)
            }
            do {
                try session.startTrack(newSource)
                try session.setSoundEnabled(true, for: newSource)
            } catch {
                actionError = "\(error)"
            }
        }
    }

    /// `setInstrument` (real disk I/O, and for a synced sample not yet downloaded, a real
    /// network wait) must not run on the main thread — same `Task.detached` bridge as
    /// `applyTestSource`'s own instrument-restore step.
    func testSound(hash: String, preset: SoundFontPresetIdentity?, key: String) {
        guard testingSoundKey == nil, let testSourceID, let path = session.soundFontPath(forHash: hash) else { return }
        testingSoundKey = key
        let session = self.session
        Task {
            let outcome = await Task.detached {
                Result { try session.setInstrument(named: path, for: testSourceID, preset: preset) }
            }.value
            testingSoundKey = nil
            if case .failure(let error) = outcome { actionError = "\(error)" }
        }
    }
}

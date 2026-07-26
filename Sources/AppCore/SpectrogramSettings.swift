import Foundation

/// Persisted spectrogram display preferences (palette, note overlay) — same "singleton JSON in
/// the settings folder" shape as `LumiSettingsFile`/`NoteColorSettingsFile`. `palette` is a raw
/// name (`String`), not `JamShackUI.SpectrogramPalette` itself: `AppCore` never depends on
/// `JamShackUI` (only the reverse, see `Package.swift`), so this file only needs to remember a
/// name, never interpret it — the SwiftUI layer (which imports both) converts via
/// `SpectrogramPalette(rawValue:)`. Previously these were plain `@State` local to
/// `MicrophoneControlsView`, lost every time that view was recreated (e.g. switching away from
/// the Microphone sub-tab and back) — moving them here persists the choice and lets the
/// "Couleurs" sub-tab show/edit the same setting.
public struct SpectrogramSettingsFile: Codable, Equatable, Sendable {
    public var palette: String
    public var showNoteOverlay: Bool

    public init(palette: String = "thermal", showNoteOverlay: Bool = false) {
        self.palette = palette
        self.showNoteOverlay = showNoteOverlay
    }
}

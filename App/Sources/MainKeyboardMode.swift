import SwiftUI
import MusicTheoryKit

extension View {
    /// Registers `mode` as driving the persistent main-keyboard bar's own coloring (mode-tone
    /// fill + scale-degree badges — see `AppModel.mainKeyboardMode`'s own doc comment) whenever
    /// `isActive` is true. Same `isActive`-driven design as `registerContextualHelp` — see that
    /// modifier's own doc comment for why `.onAppear`/`.onDisappear` can't be trusted here (tab
    /// content stays mounted across switches in this app). Also reacts to `mode` itself changing
    /// while already active (e.g. picking a different tonic/scale on the same screen), which
    /// `registerContextualHelp` never needed to since its content doesn't vary that way.
    func registerMainKeyboardMode(id: String, isActive: Bool, mode: Mode?) -> some View {
        modifier(MainKeyboardModeRegistration(id: id, isActive: isActive, mode: mode))
    }
}

private struct MainKeyboardModeRegistration: ViewModifier {
    @Environment(AppModel.self) private var appModel
    let id: String
    let isActive: Bool
    let mode: Mode?

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive, initial: true) { _, active in
                if active {
                    appModel.setMainKeyboardMode(id: id, mode: mode)
                } else {
                    appModel.clearMainKeyboardMode(id: id)
                }
            }
            .onChange(of: mode) { _, newMode in
                guard isActive else { return }
                appModel.setMainKeyboardMode(id: id, mode: newMode)
            }
    }
}

/// See `AppModel.mainKeyboardChord`'s own doc comment — root pitch class + tones (pitch
/// classes, including the root), the Chord Library's own equivalent of `Mode` for this purpose.
public struct MainKeyboardChordSpec: Equatable {
    public let root: Int
    public let tones: [Int]

    public init(root: Int, tones: [Int]) {
        self.root = root
        self.tones = tones
    }
}

extension View {
    /// Registers `chord` as driving the persistent main-keyboard bar's own centered reference
    /// voicing (see `AppModel.mainKeyboardChord`'s own doc comment) whenever `isActive` is true —
    /// the Chord Library's own counterpart to `registerMainKeyboardMode` above (same design,
    /// same reasoning for why `isActive` rather than `.onAppear`/`.onDisappear`).
    func registerMainKeyboardChord(id: String, isActive: Bool, chord: MainKeyboardChordSpec?) -> some View {
        modifier(MainKeyboardChordRegistration(id: id, isActive: isActive, chord: chord))
    }
}

private struct MainKeyboardChordRegistration: ViewModifier {
    @Environment(AppModel.self) private var appModel
    let id: String
    let isActive: Bool
    let chord: MainKeyboardChordSpec?

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive, initial: true) { _, active in
                if active {
                    appModel.setMainKeyboardChord(id: id, chord: chord)
                } else {
                    appModel.clearMainKeyboardChord(id: id)
                }
            }
            .onChange(of: chord) { _, newChord in
                guard isActive else { return }
                appModel.setMainKeyboardChord(id: id, chord: newChord)
            }
    }
}

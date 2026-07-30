import SwiftUI
import AppCore
import JamShackUI
import Localization

/// "Sons" sub-tab of the "JamShack" tab: a thin container switching between `SoundLibraryView`
/// ("Bibliotheque" — the full per-file browser: import, sync/storage management, download,
/// delete) and `FavoriteSoundsView` ("Favoris" — a flat list of favorited sounds only). Both
/// share ONE `SoundTestModeController` instance, created here, so switching between the two
/// sub-tabs never interrupts an active test (the source keeps playing, the keyboard
/// visualization keeps updating) instead of each tab owning its own independent, and inevitably
/// conflicting, copy of that state.
struct SoundsView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge
    /// Whether this screen is genuinely the one visible right now — driven by `JamShackView`
    /// (its own `subTab == .sons`) combined with `ContentView`'s own active-tab check, NOT by
    /// `.onAppear`/`.onDisappear`: those are unreliable here, since `TabView` on macOS
    /// (`.sidebarAdaptable`) keeps every tab's content alive in the background rather than
    /// tearing it down on switch, so `.onDisappear` was never firing when leaving this screen
    /// for a DIFFERENT main tab (only when switching JamShack's own sub-tabs, which really does
    /// replace the view). Real bug this caused: test mode (and the tracks it pauses/resumes,
    /// including any scene's MIDI-sourced roles) stayed stuck active/paused indefinitely after
    /// leaving for another tab.
    let isActive: Bool

    private enum SubTab: Hashable { case library, favorites }

    @State private var subTab: SubTab = .library
    /// `@State`, not a plain `let` — this view struct can be recreated by its parent (e.g. on
    /// every `isActive` change bubbling down from `ContentView`); `@State` is what makes SwiftUI
    /// keep the SAME `SoundTestModeController` instance alive across those recreations instead
    /// of silently constructing a fresh one (and losing whatever test was in progress) each time.
    @State private var controller: SoundTestModeController

    init(session: ImprovSession, bridge: SessionUIBridge, isActive: Bool) {
        self.session = session
        self.bridge = bridge
        self.isActive = isActive
        _controller = State(initialValue: SoundTestModeController(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $subTab) {
                Text(L10n.string(.appTabBibliotheque, session.currentLanguage)).tag(SubTab.library)
                Text(L10n.string(.appTabFavoris, session.currentLanguage)).tag(SubTab.favorites)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            switch subTab {
            case .library:
                SoundLibraryView(session: session, bridge: bridge, controller: controller)
            case .favorites:
                FavoriteSoundsView(session: session, bridge: bridge, controller: controller)
            }
        }
        // `initial: true` covers the very first appearance too (this screen's whole purpose is
        // browsing/testing sounds, so it starts already in test mode with the computer keyboard
        // as the source, per explicit user request) — see `isActive`'s own doc comment for why
        // this reacts to that flag instead of `.onAppear`/`.onDisappear`.
        .onChange(of: isActive, initial: true) { _, active in
            controller.setTestMode(active)
        }
    }
}

#Preview {
    let session = ImprovSession()
    return SoundsView(session: session, bridge: SessionUIBridge(session: session), isActive: true)
}

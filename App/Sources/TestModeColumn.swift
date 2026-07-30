import SwiftUI
import AppCore
import JamShackUI
import Localization

/// The "try it on a live track" column shared by `SoundLibraryView`'s detail screen and
/// `FavoriteSoundsView` — same UI, backed by the same `SoundTestModeController` instance (owned
/// by the top-level `SoundsView`) so switching between those two tabs never interrupts whatever
/// is currently playing.
struct TestModeColumn: View {
    let session: ImprovSession
    let bridge: SessionUIBridge
    let controller: SoundTestModeController

    private var testTrackState: WebConsoleTrackState? {
        guard let wireID = controller.testSourceID?.wireIDText else { return nil }
        return bridge.state.tracks.first { $0.id == wireID }
    }

    var body: some View {
        Form {
            Section {
                Toggle(L10n.string(.appToggleModeTestSon, session.currentLanguage), isOn: Binding(
                    get: { controller.isTestModeOn },
                    set: { controller.setTestMode($0) }
                ))
                if controller.isTestModeOn {
                    if controller.isChangingTestSource {
                        ProgressView().controlSize(.small)
                    } else {
                        Picker(L10n.string(.appFieldSourceTest, session.currentLanguage), selection: Binding(
                            get: { controller.testSourceID },
                            set: { controller.applyTestSource($0) }
                        )) {
                            Text(L10n.string(.appOptionAucuneFem, session.currentLanguage)).tag(TrackID?.none)
                            ForEach(controller.testableSources) { track in
                                Text(session.labelWithChannel(track)).tag(TrackID?.some(track.id))
                            }
                        }
                    }
                    if let track = testTrackState {
                        AutoCenteredKeyboardView(
                            heldPitches: track.heldPitches,
                            palette: bridge.state.palette,
                            paletteTextColors: bridge.state.paletteTextColors
                        )
                        if let chordLabel = track.chordLabel {
                            Text(chordLabel).font(.headline).foregroundStyle(Color.accentColor)
                        }
                        if let modesLabel = track.modesLabel {
                            Text(modesLabel).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(L10n.string(.appPlaceholderChoisirSourceTest, session.currentLanguage))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L10n.string(.appHeadingTesterLeSon, session.currentLanguage))
            } footer: {
                Text(L10n.string(.appHintTesterLeSon, session.currentLanguage))
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }
}

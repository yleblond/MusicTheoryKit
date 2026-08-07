import SwiftUI
import AppCore
import JamShackUI
import Localization

/// Hosts the Chord/Mode/Progression Library screens behind one horizontal segmented control,
/// with a single shared instrument picker (`FavoriteSoundPickerView`) — the "Théorie" tab.
/// Detachable into its own window on macOS/visionOS via `isDetachedWindow`, the same convention
/// `SceneLayoutView`/`GuideLectureView`/`MicrophoneControlsView`/`RunScreen` already use: this
/// view itself only draws the open/reintegrate button; `TheoryTabContent` decides (via
/// `AppModel.openAuxiliaryWindows`) whether to show this view or a `DetachedPlaceholderView` in
/// the main window.
struct TheoryView: View {
    let session: ImprovSession
    var isDetachedWindow: Bool = false

    private enum Section {
        case chords, modes, progressions
    }

    @State private var section: Section = .chords
    /// The one instrument choice shared by all three screens below — threaded down as a
    /// binding rather than each screen picking its own, per explicit request.
    @State private var auditionSoundID: String?

    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onAppear { selectDefaultSoundIfNeeded() }
        // `favoriteSounds` can still be empty when this tab first appears (the soundfont
        // library indexes asynchronously at launch) — re-apply the default once it's
        // populated, so a chord/scale/progression tap makes sound the first time it's tried
        // rather than silently doing nothing until the user notices they need to pick one.
        .onChange(of: session.favoriteSounds.map(\.id)) { selectDefaultSoundIfNeeded() }
    }

    private func selectDefaultSoundIfNeeded() {
        if auditionSoundID == nil {
            auditionSoundID = session.favoriteSounds.first?.id
        }
    }

    private var header: some View {
        HStack {
            Picker("", selection: $section) {
                Text(L10n.string(.appTabAccords, session.currentLanguage)).tag(Section.chords)
                Text(L10n.string(.appTabModes, session.currentLanguage)).tag(Section.modes)
                Text(L10n.string(.appTabProgressions, session.currentLanguage)).tag(Section.progressions)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            Spacer()

            FavoriteSoundPickerView(favoriteSounds: session.favoriteSounds, selectedID: $auditionSoundID, language: session.currentLanguage)
                .pickerStyle(.menu)
                .frame(maxWidth: 260)

            #if os(macOS) || os(visionOS)
            detachButton
            #endif
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .chords: ChordLibraryView(session: session, auditionSoundID: $auditionSoundID)
        case .modes: ModeLibraryView(session: session, auditionSoundID: $auditionSoundID)
        case .progressions: ProgressionLibraryView(session: session, auditionSoundID: $auditionSoundID)
        }
    }

    #if os(macOS) || os(visionOS)
    @ViewBuilder
    private var detachButton: some View {
        if isDetachedWindow {
            Button {
                dismissWindow(id: AuxiliaryWindowID.theorie.rawValue)
            } label: {
                Label(L10n.string(.appButtonReintegrer, session.currentLanguage), systemImage: "arrow.down.right.and.arrow.up.left")
            }
        } else {
            Button {
                openWindow(id: AuxiliaryWindowID.theorie.rawValue)
            } label: {
                Image(systemName: "rectangle.on.rectangle")
            }
        }
    }
    #endif
}

#Preview {
    TheoryView(session: ImprovSession())
}

import SwiftUI
import AppCore
import PieceModel
import JamShackUI
import Localization

/// Screen 2 of the Guide tab: mirrors `SceneLayoutView` — a title `TextField` (typing a name
/// calls `renameCurrentGuide(to:)`, which both renames an already-saved guide in place and
/// performs the FIRST save of a brand-new anonymous one), a back-to-list button, an "Enregistrer"
/// button, and the guide's own `GuideEditionView` (add/edit steps). Editing-only, per explicit
/// request — this is Composition mode's own Guide screen now, and PLAYING a guide lives in
/// Studio's own Guide tab (`StudioGuidePlayTabContent`) instead: `GuideEditionView`'s own "jouer
/// le guide" button (`onRequestLecture`) requests that cross-mode jump
/// (`AppModel.requestGuideNavigation(.playInStudio)`) rather than switching an internal Edition/
/// Lecture mode the way this screen used to.
///
/// Only ever reached once a guide is already active (by launch, or by a successful activate/
/// create on `GuideFileView`, screen 1), so `session.currentGuide` is guaranteed non-nil here.
struct GuideConfigurationView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge
    let onBackToList: () -> Void

    @Environment(AppModel.self) private var appModel

    @State private var actionError: String?
    @State private var titleDraft = ""
    @FocusState private var titleFieldFocused: Bool

    private var guide: GuideSequence? { session.currentGuide }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBackToList()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(L10n.string(.appHeadingDossierGuides, session.currentLanguage))
                if session.currentGuideRecordID != nil {
                    Button(L10n.string(.appButtonSauvegarderDansCeDossier, session.currentLanguage)) {
                        do {
                            try session.saveGuideSequence()
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
                Spacer()
            }
            .padding([.horizontal, .top])
            if let actionError {
                Text(actionError).foregroundStyle(.red).font(.caption).padding(.horizontal)
            }
            if let guide {
                TextField(
                    L10n.string(.appPlaceholderSansNom, session.currentLanguage),
                    text: $titleDraft
                )
                .font(.title2.bold())
                .textFieldStyle(.plain)
                .focused($titleFieldFocused)
                .padding([.horizontal, .top])
                .onAppear { titleDraft = guide.title }
                .onChange(of: guide.title) { _, newValue in
                    if !titleFieldFocused { titleDraft = newValue }
                }
                .onChange(of: titleFieldFocused) { wasFocused, isFocused in
                    guard wasFocused, !isFocused, titleDraft != guide.title, !titleDraft.isEmpty else { return }
                    do {
                        try session.renameCurrentGuide(to: titleDraft)
                    } catch {
                        actionError = "\(error)"
                    }
                }
            }
            GuideEditionView(
                session: session, bridge: bridge,
                onRequestLecture: { appModel.requestGuideNavigation(.playInStudio) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    let session = ImprovSession()
    return GuideConfigurationView(session: session, bridge: SessionUIBridge(session: session), onBackToList: {})
        .environment(AppModel())
}

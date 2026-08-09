import SwiftUI
import AppCore
import JamShackUI
import Localization

/// Studio's own "Guide" tab — PLAYING an already-authored guide, not editing it (editing lives in
/// Composition mode's own Guide screen, `GuideConfigurationView`, per explicit request). Reuses
/// the same guide-selection screen (`GuideFileView`) and the same playback screen
/// (`GuideLectureView`) Composition's Guide screen used to also show internally, since both act
/// on the one shared `session.currentGuide` — there's no separate "guide loaded for editing" vs
/// "for playing" (see `AppModel.GuideNavigationDestination`'s own doc comment): picking a guide
/// here also changes what Composition's own Guide screen would show if you switched there.
struct StudioGuidePlayTabContent: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    private enum Screen { case list, lecture }

    @State private var screen: Screen

    @Environment(AppModel.self) private var appModel
    #if os(macOS) || os(visionOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    init(session: ImprovSession, bridge: SessionUIBridge) {
        self.session = session
        self.bridge = bridge
        _screen = State(initialValue: (session.currentGuide?.steps.isEmpty ?? true) ? .list : .lecture)
    }

    var body: some View {
        Group {
            switch screen {
            case .list:
                GuideFileView(session: session, onLoaded: { screen = .lecture })
            case .lecture:
                #if os(macOS) || os(visionOS)
                if appModel.openAuxiliaryWindows.contains(.guideLecture) {
                    DetachedPlaceholderView(
                        message: L10n.string(.appLabelOuvertDansFenetreSeparee, session.currentLanguage),
                        language: session.currentLanguage,
                        onReintegrate: { dismissWindow(id: AuxiliaryWindowID.guideLecture.rawValue) }
                    )
                } else {
                    lectureScreen
                }
                #else
                lectureScreen
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // "Jouer le guide" from Composition mode's own Guide screen (`GuideEditionView`) lands
        // here — jump straight to Lecture (a guide is already active, since that's exactly what
        // was just being edited) instead of making the user re-pick it from the list, per
        // explicit request.
        .onChange(of: appModel.guideNavigationRequestToken) { _, _ in
            guard appModel.guideNavigationRequest == .playInStudio else { return }
            screen = .lecture
        }
    }

    /// The back-to-list chevron mirrors `GuideConfigurationView`'s own; the "Éditer le guide"
    /// button is this screen's own addition — the Lecture-side counterpart of
    /// `GuideEditionView.onRequestLecture`, requesting the opposite cross-mode jump.
    private var lectureScreen: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    screen = .list
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Button {
                    appModel.requestGuideNavigation(.editInComposition)
                } label: {
                    Label(L10n.string(.appButtonEditerLeGuide, session.currentLanguage), systemImage: "pencil")
                }
            }
            .padding([.horizontal, .top])
            GuideLectureView(session: session, bridge: bridge, onGuideStopped: { screen = .list })
        }
    }
}

#Preview {
    let session = ImprovSession()
    return StudioGuidePlayTabContent(session: session, bridge: SessionUIBridge(session: session))
        .environment(AppModel())
}

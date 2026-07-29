import SwiftUI
import AppCore
import PieceModel
import JamShackUI
import Localization

/// Screen 2 of the Guide tab: mirrors `SceneLayoutView` — a title `TextField` (typing a name
/// calls `renameCurrentGuide(to:)`, which both renames an already-saved guide in place and
/// performs the FIRST save of a brand-new anonymous one), a back-to-list button, an "Enregistrer"
/// button, and — the guide-specific addition — a segmented toggle between Edition and Lecture
/// mode over that same active guide, replacing what used to be two separate sub-tabs.
///
/// Only ever reached once a guide is already active (by launch, or by a successful activate/
/// create on `GuideFileView`, screen 1), so `session.currentGuide` is guaranteed non-nil here.
struct GuideConfigurationView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge
    let onBackToList: () -> Void

    private enum Mode { case edition, lecture }

    @State private var mode: Mode
    @State private var actionError: String?
    @State private var titleDraft = ""
    @FocusState private var titleFieldFocused: Bool

    /// A freshly created (stepless) guide defaults to Edition, since there's nothing to run yet;
    /// an already-populated guide (activated from the list) defaults to Lecture, preserving the
    /// old "activating a guide jumps straight to playing it" behavior.
    init(session: ImprovSession, bridge: SessionUIBridge, onBackToList: @escaping () -> Void) {
        self.session = session
        self.bridge = bridge
        self.onBackToList = onBackToList
        _mode = State(initialValue: (session.currentGuide?.steps.isEmpty ?? true) ? .edition : .lecture)
    }

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
            Picker("", selection: $mode) {
                Text(L10n.string(.appModeEdition, session.currentLanguage)).tag(Mode.edition)
                Text(L10n.string(.appModeLecture, session.currentLanguage)).tag(Mode.lecture)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()
            Group {
                switch mode {
                case .edition:
                    GuideEditionView(session: session, bridge: bridge, onRequestLecture: { mode = .lecture })
                case .lecture:
                    GuideLectureView(session: session, bridge: bridge, onGuideStopped: { mode = .edition })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    let session = ImprovSession()
    return GuideConfigurationView(session: session, bridge: SessionUIBridge(session: session), onBackToList: {})
}

import SwiftUI
import AppCore
import Localization

/// Screen 1 of the Composition tab: the store-based composition-description browser (list/
/// activate/delete — descriptions live in a private SwiftData store, no folder to pick anymore),
/// plus a "Nouvelle composition" button clearing `session`'s current title/sourceText/
/// instructions. Activating or creating a description here is the only way to reach screen 2,
/// `CompositionComposerView` (see `onLoaded`) — saving lives there instead, since that's where
/// the fields being saved are actually edited.
struct CompositionFileView: View {
    let session: ImprovSession
    /// Called after a description is actually made current — activated from the list or a fresh
    /// one started — `CompositionView` switches to screen 2.
    let onLoaded: () -> Void

    @State private var actionError: String?

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            newCompositionSection
            folderSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    @ViewBuilder
    private var newCompositionSection: some View {
        Section {
            Button(L10n.string(.appNouvelleComposition, session.currentLanguage)) {
                session.setCompositionTitle(nil)
                session.setSourceText("")
                session.setAdditionalCompositionInstructions(nil)
                onLoaded()
            }
        } header: {
            Text(L10n.string(.appTabFichierComposition, session.currentLanguage))
        }
    }

    @ViewBuilder
    private var folderSection: some View {
        Section {
            if session.compositionDescriptionNames.isEmpty {
                Text(L10n.string(.appPlaceholderAucunDossierCompositionIA, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(session.compositionDescriptionNames.enumerated()), id: \.offset) { index, name in
                    HStack {
                        Button(name) {
                            do {
                                try session.useCompositionDescription(named: name)
                                onLoaded()
                            } catch {
                                actionError = "\(error)"
                            }
                        }
                        Spacer()
                        Button {
                            do {
                                try session.deleteCompositionDescription(atIndex: index)
                            } catch {
                                actionError = "\(error)"
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }
            }
        } header: {
            Text(L10n.string(.appHeadingDossierCompositionIA, session.currentLanguage))
        }
    }
}

#Preview {
    CompositionFileView(session: ImprovSession(), onLoaded: {})
}

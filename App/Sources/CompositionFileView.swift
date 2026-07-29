import SwiftUI
import AppCore
import Localization

/// "Fichier" sub-tab of the Composition tab: the store-based composition-description browser
/// (list/load/save/delete — descriptions live in a private SwiftData store, no folder to pick
/// anymore). Loading a description here updates `session` directly, so switching to the
/// "Composer" sub-tab (whose fields read from `session` on appear) picks it up without any
/// direct coupling between the two sibling views.
struct CompositionFileView: View {
    let session: ImprovSession

    @State private var actionError: String?

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            folderSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
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
            Button(L10n.string(.appButtonSauvegarderDescriptionDossier, session.currentLanguage)) {
                do {
                    try session.saveCompositionDescription(as: session.compositionTitle ?? L10n.string(.fieldDescription, session.currentLanguage))
                } catch {
                    actionError = "\(error)"
                }
            }
        } header: {
            Text(L10n.string(.appHeadingDossierCompositionIA, session.currentLanguage))
        }
    }
}

#Preview {
    CompositionFileView(session: ImprovSession())
}

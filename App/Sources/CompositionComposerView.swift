import SwiftUI
import AppCore
import Localization

/// Screen 2 of the Composition tab: describe a piece in free text (title, style indications),
/// save that description to the store, and compose it via the active LLM connection (see the
/// "JamShack" tab's own "LLM" sub-tab). Only ever reached once a description is current — fresh
/// (via screen 1's "Nouvelle composition") or activated from the list — this view reads
/// `session`'s current title/sourceText/instructions on appear. `onBackToList` returns to screen 1.
struct CompositionComposerView: View {
    let session: ImprovSession
    let onBackToList: () -> Void

    @State private var title = ""
    @State private var sourceText = ""
    @State private var instructions = ""
    @State private var actionError: String?
    @State private var isComposing = false
    @State private var composeResultMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBackToList()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(L10n.string(.appHeadingDossierCompositionIA, session.currentLanguage))
                Button(L10n.string(.appButtonSauvegarderDescriptionDossier, session.currentLanguage)) {
                    do {
                        try session.saveCompositionDescription(as: session.compositionTitle ?? L10n.string(.fieldDescription, session.currentLanguage))
                    } catch {
                        actionError = "\(error)"
                    }
                }
                Spacer()
            }
            .padding([.horizontal, .top])
            Form {
                if let actionError {
                    Section { Text(actionError).foregroundStyle(.red).font(.caption) }
                }
                descriptionSection
                composeSection
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
        }
        .onAppear {
            title = session.compositionTitle ?? ""
            sourceText = session.sourceText ?? ""
            instructions = session.additionalCompositionInstructions ?? ""
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        Section {
            TextField(L10n.string(.appPlaceholderTitreMorceau, session.currentLanguage), text: $title)
                .onChange(of: title) { _, newValue in session.setCompositionTitle(newValue.isEmpty ? nil : newValue) }
            TextEditor(text: $sourceText)
                .frame(minHeight: 120)
                .onChange(of: sourceText) { _, newValue in session.setSourceText(newValue) }
            TextField(L10n.string(.appPlaceholderIndicationsStyleOpt, session.currentLanguage), text: $instructions)
                .onChange(of: instructions) { _, newValue in session.setAdditionalCompositionInstructions(newValue.isEmpty ? nil : newValue) }
        } header: {
            Text(L10n.string(.appHeadingDescriptionMorceau, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintDecrisMorceauTexteLibre, session.currentLanguage))
        }
    }

    @ViewBuilder
    private var composeSection: some View {
        Section {
            if isComposing {
                HStack { ProgressView(); Text(L10n.string(.appStatusCompositionEnCours, session.currentLanguage)) }
            } else {
                Button(L10n.string(.appButtonComposerDepuisDescription, session.currentLanguage)) { compose() }
            }
            if let composeResultMessage {
                Text(composeResultMessage).font(.caption).foregroundStyle(.green)
            }
        } header: {
            Text(L10n.string(.appHeadingCompositionIA, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintUtiliseConnexionLLMSeule, session.currentLanguage))
        }
    }

    private func compose() {
        composeResultMessage = nil
        actionError = nil
        isComposing = true
        let composedTitle = title.isEmpty ? nil : title
        Task {
            let outcome = await Task.detached {
                Result { try session.composeFromText(title: composedTitle) }
            }.value
            isComposing = false
            switch outcome {
            case .success:
                composeResultMessage = "Compose avec succes : \(session.piece?.title ?? "")"
            case .failure(let error):
                actionError = "\(error)"
            }
        }
    }
}

#Preview {
    CompositionComposerView(session: ImprovSession(), onBackToList: {})
}

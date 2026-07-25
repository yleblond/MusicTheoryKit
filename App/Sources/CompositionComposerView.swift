import SwiftUI
import AppCore

/// "Composer" sub-tab of the Composition tab: describe a piece in free text (title, style
/// indications) and compose it via the active LLM connection (see the "JamShack" tab's own
/// "LLM" sub-tab). Loading/saving a description to a folder lives in the sibling "Fichier"
/// sub-tab — this view reads `session`'s current title/sourceText/instructions on appear, so
/// a load from that sibling tab shows up here as soon as this tab is switched to.
struct CompositionComposerView: View {
    let session: ImprovSession

    @State private var title = ""
    @State private var sourceText = ""
    @State private var instructions = ""
    @State private var actionError: String?
    @State private var isComposing = false
    @State private var composeResultMessage: String?

    var body: some View {
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
        .onAppear {
            title = session.compositionTitle ?? ""
            sourceText = session.sourceText ?? ""
            instructions = session.additionalCompositionInstructions ?? ""
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        Section {
            TextField("Titre du morceau", text: $title)
                .onChange(of: title) { _, newValue in session.setCompositionTitle(newValue.isEmpty ? nil : newValue) }
            TextEditor(text: $sourceText)
                .frame(minHeight: 120)
                .onChange(of: sourceText) { _, newValue in session.setSourceText(newValue) }
            TextField("Indications de style (optionnel)", text: $instructions)
                .onChange(of: instructions) { _, newValue in session.setAdditionalCompositionInstructions(newValue.isEmpty ? nil : newValue) }
        } header: {
            Text("Description du morceau")
        } footer: {
            Text("Decris le morceau en texte libre — c'est ce texte qui sera envoye au LLM pour composer.")
        }
    }

    @ViewBuilder
    private var composeSection: some View {
        Section {
            if isComposing {
                HStack { ProgressView(); Text("Composition en cours...") }
            } else {
                Button("Composer depuis cette description") { compose() }
            }
            if let composeResultMessage {
                Text(composeResultMessage).font(.caption).foregroundStyle(.green)
            }
        } header: {
            Text("Composition IA")
        } footer: {
            Text("Utilise la connexion LLM active (JamShack > LLM).")
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
    CompositionComposerView(session: ImprovSession())
}

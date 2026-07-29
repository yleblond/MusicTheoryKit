import SwiftUI
import AppCore
import Localization

/// "Cadrages" sub-tab of Settings: manage the framing sentences (text + soundtrack) and
/// soundtrack style indications used by "Composition IA" — mirrors the CLI's own
/// `show/set/save/use/reset-text-framing` (and soundtrack equivalent) commands
/// (`Sources/JamShack/main.swift`), which had no SwiftUI counterpart until now. Adds one
/// capability the CLI never had: deleting a saved snippet (see
/// `ImprovSession.deleteTextFramingSentence(atIndex:)` and its two siblings).
struct JamShackPromptsView: View {
    let session: ImprovSession

    @State private var actionError: String?
    @State private var textFramingDraft = ""
    @State private var soundTrackFramingDraft = ""
    @State private var soundTrackInstructionsDraft = ""

    private enum SaveTarget: Identifiable {
        case textFraming, soundTrackFraming, soundTrackInstructions
        var id: Self { self }
    }
    @State private var saveTarget: SaveTarget?
    @State private var saveNameDraft = ""

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            PromptSnippetSection(
                title: L10n.string(.appHeadingCadrageTexte, session.currentLanguage),
                draft: $textFramingDraft,
                names: session.textFramingSentenceNames,
                canSave: true,
                onApply: { session.setTextFramingSentence($0) },
                onSaveAs: { saveTarget = .textFraming },
                onUse: { index in
                    try session.useTextFramingSentence(atIndex: index)
                    textFramingDraft = session.currentTextFramingSentence()
                },
                onDelete: { index in try session.deleteTextFramingSentence(atIndex: index) },
                onReset: {
                    session.resetTextFramingSentence()
                    textFramingDraft = session.currentTextFramingSentence()
                },
                onError: { actionError = $0 },
                language: session.currentLanguage
            )
            PromptSnippetSection(
                title: L10n.string(.appHeadingCadrageSoundtrack, session.currentLanguage),
                draft: $soundTrackFramingDraft,
                names: session.soundTrackFramingSentenceNames,
                canSave: true,
                onApply: { session.setSoundTrackFramingSentence($0) },
                onSaveAs: { saveTarget = .soundTrackFraming },
                onUse: { index in
                    try session.useSoundTrackFramingSentence(atIndex: index)
                    soundTrackFramingDraft = session.currentSoundTrackFramingSentence()
                },
                onDelete: { index in try session.deleteSoundTrackFramingSentence(atIndex: index) },
                onReset: {
                    session.resetSoundTrackFramingSentence()
                    soundTrackFramingDraft = session.currentSoundTrackFramingSentence()
                },
                onError: { actionError = $0 },
                language: session.currentLanguage
            )
            PromptSnippetSection(
                title: L10n.string(.appHeadingIndicationsSoundtrack, session.currentLanguage),
                draft: $soundTrackInstructionsDraft,
                names: session.soundTrackInstructionsNames,
                canSave: !soundTrackInstructionsDraft.isEmpty,
                onApply: { session.setSoundTrackCompositionInstructions($0) },
                onSaveAs: { saveTarget = .soundTrackInstructions },
                onUse: { index in
                    try session.useSoundTrackCompositionInstructions(atIndex: index)
                    soundTrackInstructionsDraft = session.currentSoundTrackCompositionInstructions() ?? ""
                },
                onDelete: { index in try session.deleteSoundTrackInstructions(atIndex: index) },
                onReset: {
                    session.resetSoundTrackCompositionInstructions()
                    soundTrackInstructionsDraft = session.currentSoundTrackCompositionInstructions() ?? ""
                },
                onError: { actionError = $0 },
                language: session.currentLanguage
            )
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .onAppear {
            textFramingDraft = session.currentTextFramingSentence()
            soundTrackFramingDraft = session.currentSoundTrackFramingSentence()
            soundTrackInstructionsDraft = session.currentSoundTrackCompositionInstructions() ?? ""
        }
        .alert(L10n.string(.appButtonSauvegarderSous, session.currentLanguage), isPresented: Binding(
            get: { saveTarget != nil },
            set: { if !$0 { saveTarget = nil } }
        )) {
            TextField(L10n.string(.fieldTitre, session.currentLanguage), text: $saveNameDraft)
            Button(L10n.string(.appButtonSauvegarderSous, session.currentLanguage)) {
                do {
                    switch saveTarget {
                    case .textFraming: try session.saveTextFramingSentence(as: saveNameDraft)
                    case .soundTrackFraming: try session.saveSoundTrackFramingSentence(as: saveNameDraft)
                    case .soundTrackInstructions: try session.saveSoundTrackCompositionInstructions(as: saveNameDraft)
                    case nil: break
                    }
                } catch {
                    actionError = "\(error)"
                }
                saveNameDraft = ""
                saveTarget = nil
            }
            Button(L10n.string(.appAnnuler, session.currentLanguage), role: .cancel) { saveTarget = nil }
        }
    }
}

/// One framing/instructions category — a `TextEditor` for the active value (synced to the
/// session via `onApply` on every change), a "Reinitialiser"/"Sauvegarder sous..." pair, and the
/// list of saved names (tap to load, trash icon to delete). Shared by all 3 categories in
/// `JamShackPromptsView` since they're identically shaped (a name + a plain text body) — only
/// `canSave` (soundtrack instructions has no default to fall back on, so saving with nothing
/// active would throw) varies structurally.
private struct PromptSnippetSection: View {
    let title: String
    @Binding var draft: String
    let names: [String]
    let canSave: Bool
    let onApply: (String) -> Void
    let onSaveAs: () -> Void
    let onUse: (Int) throws -> Void
    let onDelete: (Int) throws -> Void
    let onReset: () -> Void
    let onError: (String) -> Void
    let language: AppLanguage

    var body: some View {
        Section {
            TextEditor(text: $draft)
                .frame(minHeight: 100)
                .onChange(of: draft) { _, newValue in onApply(newValue) }
            HStack {
                Button(L10n.string(.appButtonReinitialiser, language)) { onReset() }
                Spacer()
                Button(L10n.string(.appButtonSauvegarderSous, language)) { onSaveAs() }
                    .disabled(!canSave)
            }
            if !names.isEmpty {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    HStack {
                        Button(name) {
                            do {
                                try onUse(index)
                            } catch {
                                onError("\(error)")
                            }
                        }
                        Spacer()
                        Button {
                            do {
                                try onDelete(index)
                            } catch {
                                onError("\(error)")
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
            Text(title)
        }
    }
}

#Preview {
    JamShackPromptsView(session: ImprovSession())
}

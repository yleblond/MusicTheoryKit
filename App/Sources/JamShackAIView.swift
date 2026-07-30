import SwiftUI
import UniformTypeIdentifiers
import AppCore
import LLMEngine
import Localization
#if os(macOS)
import AppKit
#endif

/// "I.A." sub-tab of Settings (renamed from "LLM", merged with the former "Cadrages" tab
/// 2026-07-30): picks the active LLM connection (used by the Composition/Enregistrement tabs'
/// "compose" actions) and tests it with a simple call, AND manages the framing sentences (text +
/// soundtrack) and soundtrack style indications used by "Composition IA" — both are "how the app
/// talks to an LLM" concerns, worth one tab instead of two. Connections themselves live in a
/// private SwiftData store (see `ImprovSession.addLLMConnection` et al.) — added either from the
/// built-in catalog (`LLMConnectionTemplates.builtIn`) or by importing a JSON file of the same
/// shape the old `LLMConnections/` folder used to hold (that folder still exists as a one-time
/// migration source on first launch, see `ImprovSession.migrateLLMConnectionsFromJSONIfNeeded`,
/// but is no longer read afterward). The framing/instructions sections mirror the CLI's own
/// `show/set/save/use/reset-text-framing` (and soundtrack equivalent) commands
/// (`Sources/JamShack/main.swift`).
struct JamShackAIView: View {
    let session: ImprovSession

    @State private var actionError: String?

    // MARK: - LLM connections
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testError: String?
    @State private var apiKeyInput = ""
    @State private var apiKeySaveMessage: String?
    @State private var showJSONImporter = false

    // MARK: - Framing/instructions (former "Cadrages" tab)
    @State private var textFramingDraft = ""
    @State private var soundTrackFramingDraft = ""
    @State private var soundTrackInstructionsDraft = ""

    private enum SaveTarget: Identifiable {
        case textFraming, soundTrackFraming, soundTrackInstructions
        var id: Self { self }
    }
    @State private var saveTarget: SaveTarget?
    @State private var saveNameDraft = ""

    #if os(macOS)
    /// Local mirror of `session.mcpServerEnabled` — a plain `UserDefaults`-backed computed
    /// property, not `@Observable`-tracked, so a `Toggle` needs `@State` of its own to react to
    /// changes (same pattern `SoundStorageView`'s `storageProfile` already uses for
    /// `DeviceStorageProfile.current`).
    @State private var mcpServerEnabled = false
    /// Briefly flips the copy button's icon to a checkmark after a successful copy — purely
    /// visual feedback, reverted automatically, never read back for any logic.
    @State private var mcpConfigJustCopied = false
    #endif

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            connectionsSection
            if let connection = session.currentLLMConnection {
                activeConnectionSection(connection)
                if let envVar = connection.apiKeyEnvVar {
                    apiKeySection(envVar: envVar, providerLabel: connection.provider)
                }
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
            #if os(macOS)
            mcpServerSection
            #endif
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .onAppear {
            apiKeyInput = session.currentLLMConnection?.apiKeyEnvVar.flatMap(session.llmAPIKey(forEnvVar:)) ?? ""
            textFramingDraft = session.currentTextFramingSentence()
            soundTrackFramingDraft = session.currentSoundTrackFramingSentence()
            soundTrackInstructionsDraft = session.currentSoundTrackCompositionInstructions() ?? ""
            #if os(macOS)
            mcpServerEnabled = session.mcpServerEnabled
            #endif
        }
        .onChange(of: session.currentLLMConnection?.apiKeyEnvVar) { _, envVar in
            apiKeySaveMessage = nil
            apiKeyInput = envVar.flatMap(session.llmAPIKey(forEnvVar:)) ?? ""
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

    #if os(macOS)
    @ViewBuilder
    private var mcpServerSection: some View {
        Section {
            Toggle(L10n.string(.appToggleServeurMCP, session.currentLanguage), isOn: $mcpServerEnabled)
                .onChange(of: mcpServerEnabled) { _, newValue in
                    do {
                        try session.setMCPServerEnabled(newValue)
                    } catch {
                        actionError = "\(error)"
                        // Reflect what actually happened (e.g. the port was already taken by
                        // something else) rather than leaving the toggle showing a state the
                        // server isn't really in.
                        mcpServerEnabled = session.mcpServerEnabled
                    }
                }
            claudeConfigCodeBlock
        } footer: {
            Text(L10n.string(.appFormatHintServeurMCP, session.currentLanguage, Int(MCPServer.defaultPort)))
        }
    }

    /// The exact JSON snippet the hint text above refers to ("add the configuration below") —
    /// kept out of the localized string itself (unlike the old, single-paragraph version of
    /// that hint) so it can be shown as its own selectable/copyable code block instead of
    /// buried in translated prose; only the `<project folder>` placeholder inside it still
    /// needs translating, everything else (JSON keys, the literal command) is language-neutral.
    private var claudeConfigSnippet: String {
        let placeholder = L10n.string(.appPlaceholderDossierDuProjet, session.currentLanguage)
        return """
        {
          "mcpServers": {
            "jamshack": {
              "command": "\(placeholder)/.build/release/JamShackMCPBridge"
            }
          }
        }
        """
    }

    @ViewBuilder
    private var claudeConfigCodeBlock: some View {
        HStack(alignment: .top) {
            Text(claudeConfigSnippet)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(claudeConfigSnippet, forType: .string)
                mcpConfigJustCopied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    mcpConfigJustCopied = false
                }
            } label: {
                Image(systemName: mcpConfigJustCopied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(L10n.string(.appButtonCopier, session.currentLanguage))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
    }
    #endif

    @ViewBuilder
    private var connectionsSection: some View {
        Section {
            if session.llmConnections.isEmpty {
                Text(L10n.string(.appPlaceholderAucuneConnexionLLM, session.currentLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(session.llmConnections.enumerated()), id: \.offset) { index, name in
                    HStack {
                        Button(name) {
                            testResult = nil
                            testError = nil
                            do {
                                try session.useLLMConnection(atIndex: index)
                            } catch {
                                actionError = "\(error)"
                            }
                        }
                        Spacer()
                        Button {
                            do {
                                try session.deleteLLMConnection(atIndex: index)
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
            Menu(L10n.string(.appButtonAjouterConnexionLLM, session.currentLanguage)) {
                Menu(L10n.string(.appButtonDepuisUnModele, session.currentLanguage)) {
                    ForEach(LLMConnectionTemplates.builtIn, id: \.name) { template in
                        Button(template.name) { addConnection(template) }
                    }
                }
                Button(L10n.string(.appButtonImporterFichierJSON, session.currentLanguage)) { showJSONImporter = true }
            }
        } header: {
            Text(L10n.string(.appHeadingConnexionsLLM, session.currentLanguage))
        }
        .fileImporter(isPresented: $showJSONImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    let data = try Data(contentsOf: url)
                    let connection = try JSONDecoder().decode(LLMConnection.self, from: data)
                    addConnection(connection)
                } catch {
                    actionError = "\(error)"
                }
            case .failure(let error):
                actionError = "\(error)"
            }
        }
    }

    private func addConnection(_ connection: LLMConnection) {
        do {
            try session.addLLMConnection(connection)
        } catch {
            actionError = "\(error)"
        }
    }

    @ViewBuilder
    private func activeConnectionSection(_ connection: LLMConnection) -> some View {
        Section {
            LabeledContent(L10n.string(.appFieldNomCapital, session.currentLanguage), value: connection.name)
            LabeledContent(L10n.string(.appFieldFournisseur, session.currentLanguage), value: connection.provider)
            LabeledContent(L10n.string(.appFieldModele, session.currentLanguage), value: connection.model)
            if isTesting {
                HStack { ProgressView(); Text(L10n.string(.appStatusTestEnCours, session.currentLanguage)) }
            } else {
                Button(L10n.string(.appButtonTesterConnexion, session.currentLanguage)) { test(connection) }
            }
            if let testResult {
                Text(testResult).font(.caption).foregroundStyle(.green)
            }
            if let testError {
                Text(testError).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text(L10n.string(.appHeadingConnexionActive, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintEnvoiePromptMinimal, session.currentLanguage))
        }
    }

    @ViewBuilder
    private func apiKeySection(envVar: String, providerLabel: String) -> some View {
        Section {
            SecureField(L10n.string(.appFormatClefAPI, session.currentLanguage, envVar), text: $apiKeyInput)
            Button(L10n.string(.appButtonSauvegarderLaClef, session.currentLanguage)) {
                do {
                    try session.setLLMAPIKey(apiKeyInput, forEnvVar: envVar)
                    apiKeySaveMessage = apiKeyInput.isEmpty ? "Clef effacee." : "Clef sauvegardee."
                } catch {
                    actionError = "\(error)"
                }
            }
            if let apiKeySaveMessage {
                Text(apiKeySaveMessage).font(.caption).foregroundStyle(.green)
            }
        } header: {
            Text(L10n.string(.appFormatClefAPI, session.currentLanguage, providerLabel))
        } footer: {
            Text(L10n.string(.appWarningClefTexteClair, session.currentLanguage))
        }
    }

    private func test(_ connection: LLMConnection) {
        testResult = nil
        testError = nil
        isTesting = true
        Task {
            let outcome = await Task.detached {
                Result { try LLMClient.generate(prompt: "Reponds uniquement par le mot OK.", connection: connection) }
            }.value
            isTesting = false
            switch outcome {
            case .success(let text):
                testResult = "Reponse : \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
            case .failure(let error):
                testError = "\(error)"
            }
        }
    }
}

/// One framing/instructions category — a `TextEditor` for the active value (synced to the
/// session via `onApply` on every change), a "Reinitialiser"/"Sauvegarder sous..." pair, and the
/// list of saved names (tap to load, trash icon to delete). Shared by all 3 categories above
/// since they're identically shaped (a name + a plain text body) — only `canSave` (soundtrack
/// instructions has no default to fall back on, so saving with nothing active would throw)
/// varies structurally.
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
    JamShackAIView(session: ImprovSession())
}

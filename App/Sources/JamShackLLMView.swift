import SwiftUI
import AppCore
import LLMEngine
import Localization

/// "LLM" sub-tab of the "JamShack" tab: pick the active LLM connection (used by the
/// Composition/Enregistrement tabs' "compose" actions) and test it with a simple call —
/// connections themselves are plain JSON files under the Reglages folder's `LLMConnections/`
/// subfolder (see `ImprovSession.setSettingsFolder`), listed automatically once that folder is
/// chosen (JamShack > Dossiers).
struct JamShackLLMView: View {
    let session: ImprovSession

    @State private var actionError: String?
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testError: String?
    @State private var apiKeyInput = ""
    @State private var apiKeySaveMessage: String?

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
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .onAppear { apiKeyInput = session.llmAPIKeys.keysByEnvVar[session.currentLLMConnection?.apiKeyEnvVar ?? ""] ?? "" }
        .onChange(of: session.currentLLMConnection?.apiKeyEnvVar) { _, envVar in
            apiKeySaveMessage = nil
            apiKeyInput = session.llmAPIKeys.keysByEnvVar[envVar ?? ""] ?? ""
        }
    }

    @ViewBuilder
    private var connectionsSection: some View {
        Section {
            if session.llmConnections.isEmpty {
                Text(L10n.string(.appPlaceholderAucuneConnexionLLM, session.currentLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(session.llmConnections.enumerated()), id: \.offset) { index, name in
                    Button(name.strippingJSONExtension) {
                        testResult = nil
                        testError = nil
                        do {
                            try session.useLLMConnection(atIndex: index)
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
            }
        } header: {
            Text(L10n.string(.appHeadingConnexionsLLM, session.currentLanguage))
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

#Preview {
    JamShackLLMView(session: ImprovSession())
}

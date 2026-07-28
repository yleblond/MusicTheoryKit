import SwiftUI
import AppCore
import Localization

/// "Langue" sub-tab of the "JamShack" tab: switches the UI language — also applies to the web
/// console and virtual keyboard pages (see `ImprovSession.currentLanguage`'s doc comment).
struct JamShackLanguageView: View {
    let session: ImprovSession

    @State private var actionError: String?

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            Section {
                Picker(L10n.string(.appFieldLangue, session.currentLanguage), selection: Binding(
                    get: { session.currentLanguage },
                    set: { newValue in
                        do {
                            try session.setLanguage(newValue)
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                )) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(Self.label(for: language)).tag(language)
                    }
                }
                // `.segmented` reads fine for 3 languages but not for 9 — a `Menu`-backed
                // `.menu` picker scales to any count without cramming everything on-screen.
                .pickerStyle(.menu)
            } header: {
                Text(L10n.string(.appHeadingLangueInterface, session.currentLanguage))
            } footer: {
                Text(L10n.string(.appHintLangueAppliqueAussi, session.currentLanguage))
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    private static func label(for language: AppLanguage) -> String {
        switch language {
        case .fr: return "Francais"
        case .en: return "English"
        case .de: return "Deutsch"
        case .ja: return "日本語"
        case .zhHans: return "简体中文"
        case .it: return "Italiano"
        case .es: return "Español"
        case .pt: return "Português"
        case .ru: return "Русский"
        }
    }
}

#Preview {
    JamShackLanguageView(session: ImprovSession())
}

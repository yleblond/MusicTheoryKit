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
                Picker("Langue", selection: Binding(
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
                #if os(iOS)
                .pickerStyle(.segmented)
                #endif
            } header: {
                Text("Langue de l'interface")
            } footer: {
                Text("S'applique aussi a la console web et au clavier virtuel.")
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
        }
    }
}

#Preview {
    JamShackLanguageView(session: ImprovSession())
}

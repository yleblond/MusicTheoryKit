import SwiftUI
import AppCore
import MusicTheoryKit
import Localization

/// "Notation" sub-tab of Reglages: switches the active chord-naming convention
/// (`NotationStyleRegistry`) used by the Chord/Mode/Progression Library screens — only one
/// concrete style ships today (`AngloAmericanNotationStyle`), but the picker already lists
/// whatever `NotationStyleRegistry.all` holds, so a future style needs no UI change here.
/// Modeled directly on `JamShackLanguageView`.
struct NotationStyleSettingsView: View {
    let session: ImprovSession

    @State private var actionError: String?

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            Section {
                Picker(L10n.string(.appFieldStyleNotation, session.currentLanguage), selection: Binding(
                    get: { session.notationStyle.id },
                    set: { newID in
                        do {
                            try session.setNotationStyle(NotationStyleRegistry.byID(newID))
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                )) {
                    ForEach(NotationStyleRegistry.all, id: \.id) { style in
                        Text(label(for: style)).tag(style.id)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text(L10n.string(.appHeadingNotation, session.currentLanguage))
            } footer: {
                Text(L10n.string(.appHintNotationAppliqueAussi, session.currentLanguage))
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    private func label(for style: any NotationStyle) -> String {
        switch style.id {
        case "angloAmerican": return L10n.string(.appOptionNotationAngloAmericaine, session.currentLanguage)
        default: return style.id
        }
    }
}

#Preview {
    NotationStyleSettingsView(session: ImprovSession())
}

import SwiftUI
import AppCore
import Localization

/// "Clavier ordinateur" sub-tab of the JamShack tab: the single on/off switch for
/// `ImprovSession.computerKeyboardInputEnabled` — off by default (see that property's own doc
/// comment for why), explicit here rather than always-on so typing anywhere else in the app
/// (aliasing a sound, naming a piece, the Guide's arrow-key navigation) never risks doubling as
/// a note trigger.
struct ComputerKeyboardSettingsView: View {
    let session: ImprovSession

    var body: some View {
        Form {
            Section {
                Toggle(L10n.string(.appToggleClavierOrdinateurActif, session.currentLanguage), isOn: Binding(
                    get: { session.computerKeyboardInputEnabled },
                    set: { session.setComputerKeyboardInputEnabled($0) }
                ))
            } header: {
                Text(L10n.string(.appTabClavierOrdinateur, session.currentLanguage))
            } footer: {
                Text(L10n.string(.appHintClavierOrdinateurActif, session.currentLanguage))
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }
}

#Preview {
    ComputerKeyboardSettingsView(session: ImprovSession())
}

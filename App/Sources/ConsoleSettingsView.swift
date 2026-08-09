import SwiftUI
import AppCore
import Localization

/// "Console" settings tab — was "Jam Session" until the collaborative flows (mode picker, host/
/// join, Game Center) and the "clavier virtuel" server moved to Studio's own new "Jam Session" tab
/// (`StudioJamSessionTabContent`), per explicit request: inviting others to play is a Studio
/// activity, not a setting. What's left here — the web console server, a read-only mirror of the
/// Run tab viewable from a browser — genuinely is a setting: something configured once and left
/// running in the background, not something reached for while performing.
struct ConsoleSettingsView: View {
    let session: ImprovSession

    @State private var webConsolePortText = "8080"

    var body: some View {
        Form {
            Section {
                ServerCard(
                    session: session,
                    title: L10n.string(.fieldConsoleWeb, session.currentLanguage),
                    caption: L10n.string(.appHintConsoleWebCaption, session.currentLanguage),
                    port: session.webConsolePort,
                    portText: $webConsolePortText,
                    start: { try session.startWebConsole(port: $0) },
                    stop: { session.stopWebConsole() }
                )
            } header: {
                Text(L10n.string(.appHeadingCetAppareil, session.currentLanguage))
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }
}

#Preview {
    ConsoleSettingsView(session: ImprovSession())
}

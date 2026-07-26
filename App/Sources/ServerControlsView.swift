import SwiftUI
import AppCore
import NetEngine
import Localization

/// Start/stop controls for the two HTTP servers `ImprovSession` already exposes (the
/// read-only web console and the playable virtual keyboard — same servers/pages `JamShack`'s
/// CLI already starts via `web-console`/`virtual-keyboard` commands), plus the actual
/// address(es) to type into a browser on ANOTHER device on the same network — `localhost`
/// only resolves from this device itself, so reaching the server from someone else's
/// phone/laptop needs the real LAN address (`LocalNetworkAddress.ipv4Addresses()`).
///
/// Works on iOS too, not just macOS: `Network.framework` (what `WebConsole`'s `HTTPServer`
/// is built on) is available on both, and iOS doesn't have a distinct "incoming network
/// connections" entitlement the way macOS's App Sandbox does — only the local-network
/// permission prompt already covered by `NSLocalNetworkUsageDescription`. The real iOS-only
/// caveat: the server only accepts connections while this app is in the foreground — a
/// backgrounded/locked app has any listening socket suspended by the OS.
struct ServerControlsView: View {
    let session: ImprovSession

    @State private var webConsolePortText = "8080"
    @State private var virtualKeyboardPortText = "8081"
    @State private var errorText: String?

    var body: some View {
        Form {
            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            serverSection(
                title: L10n.string(.fieldConsoleWeb, session.currentLanguage),
                caption: L10n.string(.appHintConsoleWebCaption, session.currentLanguage),
                port: session.webConsolePort,
                portText: $webConsolePortText,
                start: { try session.startWebConsole(port: $0) },
                stop: { session.stopWebConsole() }
            )
            serverSection(
                title: L10n.string(.fieldClavierVirtuel, session.currentLanguage),
                caption: L10n.string(.appHintClavierVirtuelCaption, session.currentLanguage),
                port: session.virtualKeyboardPort,
                portText: $virtualKeyboardPortText,
                start: { try session.startVirtualKeyboard(port: $0) },
                stop: { session.stopVirtualKeyboard() }
            )
            #if os(iOS)
            Section {
                Text(L10n.string(.appHintServeurPremierPlan, session.currentLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    @ViewBuilder
    private func serverSection(
        title: String,
        caption: String,
        port: Int?,
        portText: Binding<String>,
        start: @escaping (Int) throws -> Void,
        stop: @escaping () -> Void
    ) -> some View {
        Section {
            Text(caption).font(.caption).foregroundStyle(.secondary)
            if let port {
                ForEach(addresses(for: port), id: \.self) { url in
                    HStack {
                        Text(url).textSelection(.enabled).font(.system(.body, design: .monospaced))
                        Spacer()
                        if let shareURL = URL(string: url) {
                            ShareLink(item: shareURL, message: Text(L10n.string(.appFormatRejoinsMoiSur, session.currentLanguage, title))) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
                Button(L10n.string(.appButtonArreter, session.currentLanguage), role: .destructive) { stop() }
            } else {
                HStack {
                    Text(L10n.string(.fieldPort, session.currentLanguage))
                    TextField(L10n.string(.fieldPort, session.currentLanguage), text: portText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                }
                Button(L10n.string(.appButtonDemarrer, session.currentLanguage)) {
                    errorText = nil
                    guard let portNumber = Int(portText.wrappedValue) else {
                        errorText = "Port invalide."
                        return
                    }
                    do {
                        try start(portNumber)
                    } catch {
                        errorText = "\(error)"
                    }
                }
            }
        } header: {
            Text(title)
        }
    }

    private func addresses(for port: Int) -> [String] {
        let ipAddresses = LocalNetworkAddress.ipv4Addresses()
        let hosts = ipAddresses.isEmpty ? ["localhost"] : ipAddresses
        return hosts.map { "http://\($0):\(port)" }
    }
}

#Preview {
    ServerControlsView(session: ImprovSession())
}

import SwiftUI
import AppCore
import NetEngine
import Localization

/// One HTTP server's start/stop card (console web or clavier virtuel — same two servers
/// `ImprovSession` already exposes, same ones `JamShack`'s CLI starts via
/// `web-console`/`virtual-keyboard`) — a plain card rather than a `Form` `Section`, so two of
/// these can sit side by side in an `HStack` (see `JamSessionView`'s "Own devices" block, where
/// this now lives alongside the collaborative session under a single "Jam Session" sub-tab).
///
/// Works on iOS too, not just macOS: `Network.framework` (what `WebConsole`'s `HTTPServer` is
/// built on) is available on both, and iOS doesn't have a distinct "incoming network
/// connections" entitlement the way macOS's App Sandbox does — only the local-network
/// permission prompt already covered by `NSLocalNetworkUsageDescription`. The real iOS-only
/// caveat: the server only accepts connections while this app is in the foreground — a
/// backgrounded/locked app has any listening socket suspended by the OS.
struct ServerCard: View {
    let session: ImprovSession
    let title: String
    let caption: String
    let port: Int?
    @Binding var portText: String
    let start: (Int) throws -> Void
    let stop: () -> Void

    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(caption).font(.caption).foregroundStyle(.secondary)
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red)
            }
            if let port {
                ForEach(addresses(for: port), id: \.self) { url in
                    HStack {
                        Text(url).textSelection(.enabled).font(.system(.caption, design: .monospaced))
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
                    TextField(L10n.string(.fieldPort, session.currentLanguage), text: $portText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                }
                Button(L10n.string(.appButtonDemarrer, session.currentLanguage)) {
                    errorText = nil
                    guard let portNumber = Int(portText) else {
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
            #if os(iOS)
            Text(L10n.string(.appHintServeurPremierPlan, session.currentLanguage))
                .font(.caption2)
                .foregroundStyle(.secondary)
            #endif
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func addresses(for port: Int) -> [String] {
        let ipAddresses = LocalNetworkAddress.ipv4Addresses()
        let hosts = ipAddresses.isEmpty ? ["localhost"] : ipAddresses
        return hosts.map { "http://\($0):\(port)" }
    }
}

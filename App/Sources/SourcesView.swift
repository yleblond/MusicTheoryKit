import SwiftUI
import AppCore
import NetEngine

/// Groups the input "sources" that aren't already covered by the Run tab's own always-on
/// tracks (MIDI/computer keyboard, wired in `ContentView`): the microphone, and the
/// collaborative jam session (server/client, with local-network discovery for the client
/// side) — mirrors the terminal CLI's own "Jam Session" menu category
/// (`server`/`stop-server`/`client`/`discover`/`disconnect` commands) plus its
/// `microphone-source` command.
struct SourcesView: View {
    let session: ImprovSession

    @State private var pseudo = ""
    @State private var microphoneError: String?
    @State private var serverPortText = "7777"
    @State private var clientHostText = ""
    @State private var clientPortText = "7777"
    @State private var isDiscovering = false
    @State private var discoveredServers: [DiscoveredServer] = []
    @State private var networkError: String?

    private var isMicrophoneListening: Bool {
        session.tracks.first { $0.id == .microphone }?.isListening ?? false
    }

    var body: some View {
        Form {
            microphoneSection
            pseudoSection
            networkErrorSection
            jamSessionSections
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .onAppear { pseudo = session.localClientName }
    }

    @ViewBuilder
    private var microphoneSection: some View {
        Section {
            if let microphoneError {
                Text(microphoneError).foregroundStyle(.red).font(.caption)
            }
            if isMicrophoneListening {
                Text("Microphone actif").foregroundStyle(.green)
                Button("Arreter", role: .destructive) { session.stopTrack(.microphone) }
            } else {
                Button("Demarrer l'ecoute du microphone") {
                    microphoneError = nil
                    do {
                        try session.startTrack(.microphone)
                    } catch {
                        microphoneError = "\(error)"
                    }
                }
            }
        } header: {
            Text("Microphone")
        } footer: {
            Text("Detection d'accords/notes jouees a la voix ou a un instrument acoustique, par analyse spectrale (FFT).")
        }
    }

    private var pseudoSection: some View {
        Section {
            HStack {
                Text("Pseudo")
                Spacer()
                TextField("Pseudo", text: $pseudo)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: pseudo) { _, newValue in session.localClientName = newValue }
            }
        } header: {
            Text("Session collaborative (Jam Session)")
        }
    }

    @ViewBuilder
    private var networkErrorSection: some View {
        if let networkError {
            Section {
                Text(networkError).foregroundStyle(.red).font(.caption)
            }
        }
    }

    @ViewBuilder
    private var jamSessionSections: some View {
        switch session.networkRole {
        case .standalone:
            Section("Heberger") {
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("7777", text: $serverPortText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                }
                Button("Demarrer le serveur") { startServer() }
            }
            Section("Rejoindre") {
                HStack {
                    Text("Hote")
                    Spacer()
                    TextField("localhost", text: $clientHostText)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("7777", text: $clientPortText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                }
                Button("Se connecter") { connect() }
            }
            Section {
                if isDiscovering {
                    HStack { ProgressView(); Text("Recherche...") }
                } else {
                    Button("Rechercher sur le reseau local") { discover() }
                    if discoveredServers.isEmpty {
                        Text("Aucun serveur trouve pour l'instant.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(discoveredServers, id: \.name) { server in
                    Button(server.name) { connect(discovered: server) }
                }
            } header: {
                Text("Rechercher")
            } footer: {
                Text("Le serveur (cote 'Heberger') doit tourner sur le meme reseau local, et la permission 'Reseau local' doit etre accordee a cette app.")
            }
        case .server(let port):
            Section("Heberger") {
                Text("Serveur actif sur le port \(port)").foregroundStyle(.green)
                Button("Arreter le serveur", role: .destructive) { session.stopServer() }
            }
        case .client(let description):
            Section("Rejoindre") {
                Text("Connecte a \(description)").foregroundStyle(.green)
                Button("Se deconnecter", role: .destructive) { session.disconnectFromServer() }
            }
        }
    }

    private func startServer() {
        networkError = nil
        session.localClientName = pseudo
        guard let port = Int(serverPortText) else { networkError = "Port invalide."; return }
        do {
            try session.startServer(port: port)
        } catch {
            networkError = "\(error)"
        }
    }

    private func connect() {
        networkError = nil
        session.localClientName = pseudo
        guard let port = Int(clientPortText) else { networkError = "Port invalide."; return }
        do {
            try session.connectToServer(host: clientHostText.isEmpty ? "localhost" : clientHostText, port: port)
        } catch {
            networkError = "\(error)"
        }
    }

    private func connect(discovered server: DiscoveredServer) {
        networkError = nil
        session.localClientName = pseudo
        do {
            try session.connectToServer(discovered: server)
        } catch {
            networkError = "\(error)"
        }
    }

    /// `discoverServers` blocks its calling thread for the whole search window — bounced off
    /// the main thread here so the UI stays responsive (spinner) instead of freezing for
    /// ~2 seconds, same technique `SessionUIBridge` already uses to poll `ImprovSession`
    /// from off the main thread.
    private func discover() {
        networkError = nil
        discoveredServers = []
        isDiscovering = true
        Task {
            let found = await Task.detached { session.discoverServers(timeout: 2.0) }.value
            isDiscovering = false
            discoveredServers = found
        }
    }
}

#Preview {
    SourcesView(session: ImprovSession())
}

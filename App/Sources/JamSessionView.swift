import SwiftUI
import AppCore
import NetEngine

/// Second sub-tab of the "JamShack" tab: the collaborative jam session (server/client, with
/// local-network discovery for the client side) — mirrors the terminal CLI's own "Jam
/// Session" menu category (`server`/`stop-server`/`client`/`discover`/`disconnect` commands).
///
/// Presented as an explicit 3-way choice — Isole / Organisateur / Participant — rather than
/// showing every control at once (the previous design showed "Heberger", "Rejoindre" AND
/// "Rechercher" simultaneously while `networkRole == .standalone`, which is cluttered and
/// doesn't tell the user which of those three things they're actually trying to do). The mode
/// picker only matters while `networkRole` is `.standalone` — once a server/client connection
/// is actually live, the screen shows that connection's own status regardless of the picker
/// (there's nothing left to choose at that point).
struct JamSessionView: View {
    let session: ImprovSession

    private enum CollaborationMode: String, CaseIterable, Identifiable {
        case isolated, organizer, participant
        var id: Self { self }
        var label: String {
            switch self {
            case .isolated: return "Isole"
            case .organizer: return "Organisateur"
            case .participant: return "Participant"
            }
        }
    }

    @State private var mode: CollaborationMode = .isolated
    @State private var pseudo = ""
    @State private var serverPortText = "7777"
    @State private var clientHostText = ""
    @State private var clientPortText = "7777"
    @State private var isDiscovering = false
    @State private var discoveredServers: [DiscoveredServer] = []
    @State private var networkError: String?

    var body: some View {
        Form {
            modeSection
            networkErrorSection
            content
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .onAppear {
            pseudo = session.localClientName
            // If a connection is already live (e.g. this tab was revisited), reflect it in
            // the picker instead of silently defaulting back to "Isole".
            switch session.networkRole {
            case .standalone: break
            case .server: mode = .organizer
            case .client: mode = .participant
            }
        }
    }

    @ViewBuilder
    private var modeSection: some View {
        Section {
            Picker("Mode", selection: $mode) {
                ForEach(CollaborationMode.allCases) { Text($0.label).tag($0) }
            }
            #if os(iOS)
            .pickerStyle(.segmented)
            #endif
        } header: {
            Text("Session collaborative (Jam Session)")
        }
        .disabled({
            switch session.networkRole {
            case .standalone: return false
            default: return true // a live connection is already committed to its own mode
            }
        }())
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
    private var pseudoSection: some View {
        Section {
            HStack {
                Text("Pseudo")
                Spacer()
                TextField("Pseudo", text: $pseudo)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: pseudo) { _, newValue in session.localClientName = newValue }
            }
        } footer: {
            Text("Le nom sous lequel les autres participants te voient.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.networkRole {
        case .standalone:
            switch mode {
            case .isolated: isolatedSection
            case .organizer:
                pseudoSection
                hostSection
            case .participant:
                pseudoSection
                joinSection
                discoverSection
            }
        case .server(let port):
            pseudoSection
            Section("Heberger") {
                Text("Serveur actif sur le port \(port)").foregroundStyle(.green)
                Button("Arreter le serveur", role: .destructive) { session.stopServer() }
            }
        case .client(let description):
            pseudoSection
            Section("Rejoindre") {
                Text("Connecte a \(description)").foregroundStyle(.green)
                Button("Se deconnecter", role: .destructive) { session.disconnectFromServer() }
            }
        }
    }

    @ViewBuilder
    private var isolatedSection: some View {
        Section {
            Text("Mode isole : aucune session collaborative active. Branche autant d'equipement (MIDI, microphone) que necessaire directement a cet appareil, ou invite d'autres personnes a jouer via les claviers virtuels (JamShack > Serveurs).")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var hostSection: some View {
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
    }

    @ViewBuilder
    private var joinSection: some View {
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
    }

    @ViewBuilder
    private var discoverSection: some View {
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
            Text("Le serveur (cote 'Organisateur') doit tourner sur le meme reseau local, et la permission 'Reseau local' doit etre accordee a cette app.")
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
    JamSessionView(session: ImprovSession())
}

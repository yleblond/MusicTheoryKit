import SwiftUI
import AppCore
import NetEngine
import GameKit

/// Second sub-tab of the "JamShack" tab: the collaborative jam session — either over the
/// local network (server/client, with Bonjour discovery for the client side — mirrors the
/// terminal CLI's own "Jam Session" menu category) or over the internet via Game Center
/// matchmaking (`GameCenterCoordinator`/`ImprovSession.startGameCenterServer`/
/// `joinGameCenterSession`).
///
/// Presented as an explicit 5-way choice — Isole / Jam locale-organisateur /
/// Jam locale-participant / Jam Game Center-organisateur / Jam Game Center-participant —
/// rather than showing every control at once. The mode picker only matters while
/// `networkRole == .standalone`; once a server/client connection is actually live (either
/// transport), the screen shows that connection's own status regardless of the picker.
struct JamSessionView: View {
    let session: ImprovSession

    private enum CollaborationMode: String, CaseIterable, Identifiable {
        case isolated, localOrganizer, localParticipant, gameCenterOrganizer, gameCenterParticipant
        var id: Self { self }
        var label: String {
            switch self {
            case .isolated: return "Isole"
            case .localOrganizer: return "Jam locale - organisateur"
            case .localParticipant: return "Jam locale - participant"
            case .gameCenterOrganizer: return "Jam Game Center - organisateur"
            case .gameCenterParticipant: return "Jam Game Center - participant"
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
    @State private var gameCenter = GameCenterCoordinator()

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
            case .server: mode = .localOrganizer
            case .client: mode = .localParticipant
            case .gameCenterServer: mode = .gameCenterOrganizer
            case .gameCenterClient: mode = .gameCenterParticipant
            }
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .gameCenterOrganizer || newMode == .gameCenterParticipant {
                gameCenter.authenticateIfNeeded()
            }
        }
        .sheet(isPresented: Binding(
            get: { gameCenter.presentedController != nil },
            set: { if !$0 { gameCenter.dismissPresentedController() } }
        )) {
            if let controller = gameCenter.presentedController {
                PresentedControllerView(controller: controller)
            }
        }
    }

    @ViewBuilder
    private var modeSection: some View {
        Section {
            Picker("Mode", selection: $mode) {
                ForEach(CollaborationMode.allCases) { Text($0.label).tag($0) }
            }
        } header: {
            Text("Session collaborative (Jam Session)")
        }
        .disabled(session.networkRole != .standalone)
    }

    @ViewBuilder
    private var networkErrorSection: some View {
        if let networkError {
            Section { Text(networkError).foregroundStyle(.red).font(.caption) }
        }
        if let matchError = gameCenter.matchError {
            Section { Text(matchError).foregroundStyle(.red).font(.caption) }
        }
        if let authError = gameCenter.authenticationError {
            Section { Text("Game Center : \(authError)").foregroundStyle(.red).font(.caption) }
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
            case .localOrganizer:
                pseudoSection
                hostSection
            case .localParticipant:
                pseudoSection
                joinSection
                discoverSection
            case .gameCenterOrganizer:
                pseudoSection
                gameCenterOrganizerSection
            case .gameCenterParticipant:
                pseudoSection
                gameCenterParticipantSection
            }
        case .server(let port):
            pseudoSection
            Section("Heberger (reseau local)") {
                Text("Serveur actif sur le port \(port)").foregroundStyle(.green)
                Button("Arreter le serveur", role: .destructive) { session.stopServer() }
            }
        case .client(let description):
            pseudoSection
            Section("Rejoindre (reseau local)") {
                Text("Connecte a \(description)").foregroundStyle(.green)
                Button("Se deconnecter", role: .destructive) { session.disconnectFromServer() }
            }
        case .gameCenterServer:
            pseudoSection
            Section("Organisateur Game Center") {
                Text("Session Game Center active").foregroundStyle(.green)
                Button("Arreter la session", role: .destructive) { session.stopServer() }
            }
        case .gameCenterClient(let description):
            pseudoSection
            Section("Participant Game Center") {
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
        Section("Heberger (reseau local)") {
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
        Section("Rejoindre (reseau local)") {
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
            Text("Le serveur (cote 'Jam locale - organisateur') doit tourner sur le meme reseau local, et la permission 'Reseau local' doit etre accordee a cette app.")
        }
    }

    @ViewBuilder
    private var gameCenterOrganizerSection: some View {
        Section {
            if !gameCenter.isAuthenticated {
                Text("Connexion a Game Center...").foregroundStyle(.secondary)
            } else {
                Button("Inviter / trouver des participants...") {
                    session.localClientName = pseudo
                    gameCenter.presentMatchmaker { match in
                        do {
                            try session.startGameCenterServer(with: match)
                        } catch {
                            networkError = "\(error)"
                        }
                    }
                }
            }
        } header: {
            Text("Organisateur Game Center")
        } footer: {
            Text("Ouvre la fenetre Game Center pour inviter des amis ou trouver automatiquement des participants, via internet (pas besoin du meme reseau local).")
        }
    }

    @ViewBuilder
    private var gameCenterParticipantSection: some View {
        Section {
            if !gameCenter.isAuthenticated {
                Text("Connexion a Game Center...").foregroundStyle(.secondary)
            } else {
                Button("Rejoindre via Game Center...") {
                    session.localClientName = pseudo
                    gameCenter.presentMatchmaker { match in
                        do {
                            try session.joinGameCenterSession(with: match)
                        } catch {
                            networkError = "\(error)"
                        }
                    }
                }
            }
        } header: {
            Text("Participant Game Center")
        } footer: {
            Text("Accepte une invitation Game Center recue, ou trouve automatiquement une session ouverte.")
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

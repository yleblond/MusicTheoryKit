import SwiftUI
import AppCore
import NetEngine
import GameKit
import Localization

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
        func label(_ language: AppLanguage) -> String {
            switch self {
            case .isolated: return L10n.string(.appModeIsole, language)
            case .localOrganizer: return L10n.string(.appModeJamLocaleOrganisateur, language)
            case .localParticipant: return L10n.string(.appModeJamLocaleParticipant, language)
            case .gameCenterOrganizer: return L10n.string(.appModeJamGameCenterOrganisateur, language)
            case .gameCenterParticipant: return L10n.string(.appModeJamGameCenterParticipant, language)
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
    @State private var webConsolePortText = "8080"
    @State private var virtualKeyboardPortText = "8081"

    var body: some View {
        Form {
            ownDevicesSection
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

    /// The two HTTP servers (console web, clavier virtuel) side by side — merged into this same
    /// sub-tab (2026-07-26, used to be its own "Serveurs" sub-tab) since both this block and the
    /// collaborative session below are fundamentally the same idea: other devices reaching this
    /// one. See `ServerCard`.
    @ViewBuilder
    private var ownDevicesSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                ServerCard(
                    session: session,
                    title: L10n.string(.fieldConsoleWeb, session.currentLanguage),
                    caption: L10n.string(.appHintConsoleWebCaption, session.currentLanguage),
                    port: session.webConsolePort,
                    portText: $webConsolePortText,
                    start: { try session.startWebConsole(port: $0) },
                    stop: { session.stopWebConsole() }
                )
                ServerCard(
                    session: session,
                    title: L10n.string(.fieldClavierVirtuel, session.currentLanguage),
                    caption: L10n.string(.appHintClavierVirtuelCaption, session.currentLanguage),
                    port: session.virtualKeyboardPort,
                    portText: $virtualKeyboardPortText,
                    start: { try session.startVirtualKeyboard(port: $0) },
                    stop: { session.stopVirtualKeyboard() }
                )
            }
        } header: {
            Text(L10n.string(.appHeadingCetAppareil, session.currentLanguage))
        }
    }

    @ViewBuilder
    private var modeSection: some View {
        Section {
            Picker(L10n.string(.fieldModeReconnaissance, session.currentLanguage), selection: $mode) {
                ForEach(CollaborationMode.allCases) { Text($0.label(session.currentLanguage)).tag($0) }
            }
        } header: {
            Text(L10n.string(.appHeadingAppareilsConnectes, session.currentLanguage))
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
            Section { Text(L10n.string(.appFormatGameCenterErreur, session.currentLanguage, authError)).foregroundStyle(.red).font(.caption) }
        }
    }

    @ViewBuilder
    private var pseudoSection: some View {
        Section {
            HStack {
                Text(L10n.string(.fieldPseudo, session.currentLanguage))
                Spacer()
                TextField(L10n.string(.fieldPseudo, session.currentLanguage), text: $pseudo)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: pseudo) { _, newValue in session.localClientName = newValue }
            }
        } footer: {
            Text(L10n.string(.appHintNomAfficheParticipants, session.currentLanguage))
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
            Section(L10n.string(.appSectionHebergerReseauLocal, session.currentLanguage)) {
                Text(L10n.string(.appFormatServeurActifPort, session.currentLanguage, "\(port)")).foregroundStyle(.green)
                Button(L10n.string(.appButtonArreterLeServeur, session.currentLanguage), role: .destructive) { session.stopServer() }
            }
        case .client(let description):
            pseudoSection
            Section(L10n.string(.appSectionRejoindreReseauLocal, session.currentLanguage)) {
                Text(L10n.string(.appFormatConnecteA, session.currentLanguage, description)).foregroundStyle(.green)
                Button(L10n.string(.appButtonSeDeconnecter, session.currentLanguage), role: .destructive) { session.disconnectFromServer() }
            }
        case .gameCenterServer:
            pseudoSection
            Section(L10n.string(.appSectionOrganisateurGameCenter, session.currentLanguage)) {
                Text(L10n.string(.appLabelSessionGameCenterActive, session.currentLanguage)).foregroundStyle(.green)
                Button(L10n.string(.appButtonArreterLaSession, session.currentLanguage), role: .destructive) { session.stopServer() }
            }
        case .gameCenterClient(let description):
            pseudoSection
            Section(L10n.string(.appSectionParticipantGameCenter, session.currentLanguage)) {
                Text(L10n.string(.appFormatConnecteA, session.currentLanguage, description)).foregroundStyle(.green)
                Button(L10n.string(.appButtonSeDeconnecter, session.currentLanguage), role: .destructive) { session.disconnectFromServer() }
            }
        }
    }

    @ViewBuilder
    private var isolatedSection: some View {
        Section {
            Text(L10n.string(.appHintModeIsole, session.currentLanguage))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var hostSection: some View {
        Section(L10n.string(.appSectionHebergerReseauLocal, session.currentLanguage)) {
            HStack {
                Text(L10n.string(.fieldPort, session.currentLanguage))
                Spacer()
                TextField(L10n.string(.appPlaceholder7777, session.currentLanguage), text: $serverPortText)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .multilineTextAlignment(.trailing)
            }
            Button(L10n.string(.appButtonDemarrerLeServeur, session.currentLanguage)) { startServer() }
        }
    }

    @ViewBuilder
    private var joinSection: some View {
        Section(L10n.string(.appSectionRejoindreReseauLocal, session.currentLanguage)) {
            HStack {
                Text(L10n.string(.fieldHote, session.currentLanguage))
                Spacer()
                TextField(L10n.string(.appPlaceholderLocalhost, session.currentLanguage), text: $clientHostText)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text(L10n.string(.fieldPort, session.currentLanguage))
                Spacer()
                TextField(L10n.string(.appPlaceholder7777, session.currentLanguage), text: $clientPortText)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .multilineTextAlignment(.trailing)
            }
            Button(L10n.string(.appButtonSeConnecter, session.currentLanguage)) { connect() }
        }
    }

    @ViewBuilder
    private var discoverSection: some View {
        Section {
            if isDiscovering {
                HStack { ProgressView(); Text(L10n.string(.appStatusRecherche, session.currentLanguage)) }
            } else {
                Button(L10n.string(.appButtonRechercherReseauLocal, session.currentLanguage)) { discover() }
                if discoveredServers.isEmpty {
                    Text(L10n.string(.appPlaceholderAucunServeurTrouve, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(discoveredServers, id: \.name) { server in
                Button(server.name) { connect(discovered: server) }
            }
        } header: {
            Text(L10n.string(.appHeadingRechercher, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintServeurReseauLocal, session.currentLanguage))
        }
    }

    @ViewBuilder
    private var gameCenterOrganizerSection: some View {
        Section {
            if !gameCenter.isAuthenticated {
                Text(L10n.string(.appStatusConnexionGameCenter, session.currentLanguage)).foregroundStyle(.secondary)
            } else {
                Button(L10n.string(.appButtonInviterTrouverParticipants, session.currentLanguage)) {
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
            Text(L10n.string(.appSectionOrganisateurGameCenter, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintOuvreFenetreGameCenterOrganisateur, session.currentLanguage))
        }
    }

    @ViewBuilder
    private var gameCenterParticipantSection: some View {
        Section {
            if !gameCenter.isAuthenticated {
                Text(L10n.string(.appStatusConnexionGameCenter, session.currentLanguage)).foregroundStyle(.secondary)
            } else {
                Button(L10n.string(.appButtonRejoindreViaGameCenter, session.currentLanguage)) {
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
            Text(L10n.string(.appSectionParticipantGameCenter, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintAccepteInvitationGameCenter, session.currentLanguage))
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

import SwiftUI
import AppCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// First sub-tab of the "JamShack" tab: pick every folder the app needs, mirroring the CLI's
/// own `catJamShack` menu category one-for-one (morceaux/sons/soundtracks/guides/scenes/
/// reglages/composition IA) — the single place all seven live now, instead of one-off pickers
/// scattered per screen (which is what left the scene folder with no way to browse it after
/// the scene screen was switched to single-file export/import).
struct JamShackFoldersView: View {
    let session: ImprovSession

    @State private var defaultRootPath: String?
    @State private var defaultRootError: String?
    @State private var showRootImporter = false

    var body: some View {
        Form {
            defaultFoldersSection
            Section {
                FolderPickerRow(
                    title: "Morceaux",
                    currentPath: session.pieceFolder,
                    fileCount: session.pieceFiles.isEmpty ? nil : session.pieceFiles.count
                ) { try session.listPieceFiles(in: $0) }
                FolderPickerRow(
                    title: "Sons (samples)",
                    currentPath: session.sampleFolder,
                    fileCount: session.sampleFiles.isEmpty ? nil : session.sampleFiles.count
                ) { try session.listSampleFiles(in: $0) }
                FolderPickerRow(
                    title: "Soundtracks",
                    currentPath: session.soundTrackFolder,
                    fileCount: session.soundTrackFiles.isEmpty ? nil : session.soundTrackFiles.count
                ) { try session.listSoundTrackFiles(in: $0) }
                FolderPickerRow(
                    title: "Guides",
                    currentPath: session.guideFolder,
                    fileCount: session.guideFiles.isEmpty ? nil : session.guideFiles.count
                ) { try session.listGuideFiles(in: $0) }
                FolderPickerRow(
                    title: "Scenes",
                    currentPath: session.sceneFolder,
                    fileCount: session.sceneFiles.isEmpty ? nil : session.sceneFiles.count
                ) { try session.listSceneFiles(in: $0) }
            } header: {
                Text("Contenus")
            }
            Section {
                FolderPickerRow(title: "Reglages", currentPath: session.settingsFolder, fileCount: nil) {
                    try session.setSettingsFolder($0)
                }
                FolderPickerRow(title: "Composition IA (prompts)", currentPath: session.promptsFolder, fileCount: nil) {
                    try session.setPromptsFolder($0)
                }
            } header: {
                Text("Configuration")
            } footer: {
                Text("Cree les sous-dossiers necessaires s'ils n'existent pas encore.")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        #if os(iOS)
        .fileImporter(isPresented: $showRootImporter, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): applyRootFolder(url)
            case .failure(let error): defaultRootError = "\(error)"
            }
        }
        #endif
    }

    @ViewBuilder
    private var defaultFoldersSection: some View {
        Section {
            if let defaultRootPath {
                Text(defaultRootPath).font(.caption).foregroundStyle(.secondary)
            }
            if let defaultRootError {
                Text(defaultRootError).font(.caption).foregroundStyle(.red)
            }
            Button(defaultRootPath == nil ? "Choisir/creer le dossier JamShack..." : "Changer de dossier JamShack...") {
                #if os(macOS)
                pickRootFolderOnMac()
                #else
                showRootImporter = true
                #endif
            }
        } header: {
            Text("Dossiers par defaut")
        } footer: {
            Text("Cree/utilise Composition IA, Pieces, Scenes, Sequences, SoundFonts et SoundTracks a l'interieur du dossier choisi — iCloud Drive > JamShack par defaut. Retenu au prochain lancement.")
        }
    }

    #if os(macOS)
    private func pickRootFolderOnMac() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.message = "Choisis ou cree le dossier JamShack (iCloud Drive recommande)"
        panel.directoryURL = iCloudDriveURLIfAvailable()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyRootFolder(url)
    }
    #endif

    private func applyRootFolder(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            defaultRootError = "Acces refuse a ce dossier."
            return
        }
        defaultRootError = nil
        DefaultFolderBookmark.save(url)
        defaultRootPath = url.path
        // `configureDefaultFolders` does ~8 synchronous disk operations (mkdir + several
        // JSON loads via `setSettingsFolder`) — this is called straight from a
        // `.fileImporter`/document-picker completion, which runs on the main thread as part
        // of the picker's own dismissal animation. Over an iCloud Drive-backed root (files not
        // yet locally cached), that can take long enough to trip the OS's ~5s main-thread
        // watchdog and get the app SIGKILLed — a real crash observed on-device, not
        // hypothetical (crash log: `documentPicker(_:didPickDocumentsAt:)` -> `applyRootFolder`
        // -> `configureDefaultFolders` -> blocked in `Data(contentsOf:)`/`mkdirat`). `session`
        // is already designed to be called from a non-main thread (see its own concurrency
        // doc comments) — nothing here needs the result back synchronously.
        Task.detached {
            configureDefaultFolders(in: url, session: session)
        }
    }
}

#Preview {
    JamShackFoldersView(session: ImprovSession())
}

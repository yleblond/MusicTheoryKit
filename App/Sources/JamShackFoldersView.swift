import SwiftUI
import AppCore
import UniformTypeIdentifiers
import Localization
#if os(macOS)
import AppKit
#endif

/// First sub-tab of the "JamShack" tab: pick every folder the app still needs a real
/// user-chosen location for. Pieces/scenes/guides/soundtracks/composition descriptions/prompt
/// snippets all moved to a private SwiftData store (no folder to pick anymore, see each
/// feature's own `migrate...FromJSONIfNeeded`) — only sounds (soundfont files, which stay
/// files on purpose), settings (a one-time migration source), and composition IA (its `Export`
/// subfolder still needs a real location) still have a folder concept here.
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
                    title: L10n.string(.appLabelDossierSons, session.currentLanguage),
                    currentPath: session.sampleFolder,
                    fileCount: session.sampleFiles.isEmpty ? nil : session.sampleFiles.count,
                    language: session.currentLanguage
                ) { try session.listSampleFiles(in: $0) }
                FolderPickerRow(title: L10n.string(.appLabelDossierReglages, session.currentLanguage), currentPath: session.settingsFolder, fileCount: nil, language: session.currentLanguage) {
                    try session.setSettingsFolder($0)
                }
                FolderPickerRow(title: L10n.string(.appLabelDossierCompositionIA, session.currentLanguage), currentPath: session.promptsFolder, fileCount: nil, language: session.currentLanguage) {
                    try session.setPromptsFolder($0)
                }
            } header: {
                Text(L10n.string(.appHeadingConfiguration, session.currentLanguage))
            } footer: {
                Text(L10n.string(.appHintCreeSousDossiers, session.currentLanguage))
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
            Button(defaultRootPath == nil ? L10n.string(.appButtonChoisirCreerDossierJamShack, session.currentLanguage) : L10n.string(.appButtonChangerDossierJamShack, session.currentLanguage)) {
                #if os(macOS)
                pickRootFolderOnMac()
                #else
                showRootImporter = true
                #endif
            }
        } header: {
            Text(L10n.string(.appHeadingDossiersParDefaut, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintDossiersParDefautDetail, session.currentLanguage))
        }
    }

    #if os(macOS)
    private func pickRootFolderOnMac() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.string(.appButtonChoisir, session.currentLanguage)
        panel.message = L10n.string(.appHintChoisisCreeDossierJamShack, session.currentLanguage)
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

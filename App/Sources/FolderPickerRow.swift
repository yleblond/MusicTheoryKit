import SwiftUI
import UniformTypeIdentifiers
import Localization

/// One "pick a folder, remember it, show what was found in it" row — the GUI counterpart of
/// the CLI's `catJamShack` category, where each entry prompts for a path and hands it to a
/// `list*Files(in:)`/`set*Folder(_:)` call on `ImprovSession`. Shared across every folder
/// category (pieces/samples/soundtracks/guides/scenes/settings/prompts) instead of repeating
/// the `.fileImporter` + security-scoped-access dance seven times: this app is sandboxed
/// (`com.apple.security.app-sandbox`), so — unlike the CLI, a plain unsandboxed process that
/// can just accept a typed path — a real Open panel (what `.fileImporter` presents) is the
/// only way in, on both iOS and macOS.
///
/// Access only lasts for as long as the app keeps running (no persisted security-scoped
/// bookmark yet) — picking again after a relaunch is the accepted tradeoff for now.
struct FolderPickerRow: View {
    let title: String
    let currentPath: String?
    let fileCount: Int?
    let language: AppLanguage
    let onPick: (String) throws -> Void

    @State private var showImporter = false
    @State private var accessedURL: URL?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button(currentPath == nil ? L10n.string(.appChoisirEllipsis, language) : L10n.string(.appChangerEllipsis, language)) {
                    showImporter = true
                }
            }
            if let currentPath {
                Text(currentPath).font(.caption).foregroundStyle(.secondary)
            }
            if let fileCount {
                Text(L10n.string(.appFormatFichiersTrouves, language, fileCount)).font(.caption).foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                accessedURL?.stopAccessingSecurityScopedResource()
                if url.startAccessingSecurityScopedResource() {
                    accessedURL = url
                    error = nil
                    do { try onPick(url.path) } catch { self.error = "\(error)" }
                }
            case .failure(let failure):
                error = "\(failure)"
            }
        }
    }
}

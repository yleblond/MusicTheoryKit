import SwiftUI
import AppCore
import Localization
import SoundFontModel

/// Shown from the info ("i") button on a library row — everything already known about a
/// soundfont from the index (name, size, sync state, origin, tags), plus whatever the file's
/// own `.sf2` `INFO` chunk carries (bank name, engineer, copyright/license, comments, the
/// software used to author it — see `SoundFontPresetReader.info(at:)`), read lazily only while
/// this sheet is open and only if the file is actually downloaded on this device.
struct SoundFontInfoSheet: View {
    let session: ImprovSession
    let entry: SoundFontEntry
    let isDownloaded: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var fileInfo: SoundFontInfo?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    row(L10n.string(.appLabelNomFichier, session.currentLanguage), entry.fileName)
                    row(L10n.string(.appLabelTaille, session.currentLanguage), ByteCountFormatter.string(fromByteCount: entry.fileSize, countStyle: .file))
                    row(L10n.string(.appLabelAjouteLe, session.currentLanguage), Self.dateFormatter.string(from: entry.dateAdded))
                    row(L10n.string(.appLabelOrigine, session.currentLanguage), originText)
                    if !entry.userTags.isEmpty {
                        row(L10n.string(.appLabelEtiquettes, session.currentLanguage), entry.userTags.joined(separator: ", "))
                    }
                } header: {
                    Text(entry.displayName)
                }

                Section {
                    if !isDownloaded {
                        Text(L10n.string(.appHintTelechargerPourMetadonnees, session.currentLanguage))
                            .font(.caption).foregroundStyle(.secondary)
                    } else if isLoading {
                        ProgressView().controlSize(.small)
                    } else if let fileInfo, !fileInfo.isEmpty {
                        if let bankName = fileInfo.bankName { row(L10n.string(.appLabelBanque, session.currentLanguage), bankName) }
                        if let soundEngine = fileInfo.soundEngine { row(L10n.string(.appLabelMoteurSonore, session.currentLanguage), soundEngine) }
                        if let creationDate = fileInfo.creationDate { row(L10n.string(.appLabelDateCreationFichier, session.currentLanguage), creationDate) }
                        if let engineer = fileInfo.engineer { row(L10n.string(.appLabelIngenieur, session.currentLanguage), engineer) }
                        if let product = fileInfo.product { row(L10n.string(.appLabelProduit, session.currentLanguage), product) }
                        if let copyright = fileInfo.copyright { row(L10n.string(.appLabelCopyright, session.currentLanguage), copyright) }
                        if let comment = fileInfo.comment { row(L10n.string(.appLabelCommentaire, session.currentLanguage), comment) }
                        if let software = fileInfo.software { row(L10n.string(.appLabelLogiciel, session.currentLanguage), software) }
                    } else {
                        Text(L10n.string(.appPlaceholderAucuneMetadonnee, session.currentLanguage))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L10n.string(.appHeadingMetadonneesFichier, session.currentLanguage))
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string(.appButtonFermer, session.currentLanguage)) { dismiss() }
                }
            }
        }
        .task {
            guard isDownloaded, let path = session.soundFontPath(forHash: entry.hash) else { return }
            isLoading = true
            // A tiny file read (the `INFO` chunk sits near the start, well before the bulk
            // sample data) — still off the main actor on principle, same as every other disk
            // read this app does from a UI action.
            fileInfo = await Task.detached {
                try? SoundFontPresetReader.info(at: URL(fileURLWithPath: path))
            }.value
            isLoading = false
        }
    }

    private var originText: String {
        switch entry.origin {
        case .userImported: return L10n.string(.appOptionOrigineImporte, session.currentLanguage)
        case .curated: return L10n.string(.appOptionOrigineCuree, session.currentLanguage)
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

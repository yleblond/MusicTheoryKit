import SwiftUI
import UniformTypeIdentifiers
import AppCore
import Localization

/// "Fichier" sub-tab of the Morceaux tab: which piece is loaded, the demo piece, and the
/// store-based piece browser (list/load/save/delete — pieces live in a private SwiftData
/// store, no folder to pick anymore). Playback lives in the "Play" sub-tab.
struct PiecesFileView: View {
    let session: ImprovSession
    /// Called after a piece is actually loaded (demo, imported, or from the folder) —
    /// `PiecesView` switches to the "Play" sub-tab, per explicit user request.
    let onLoaded: () -> Void

    @State private var actionError: String?
    @State private var showFileImporter = false
    @State private var isImporting = false

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            pieceSection
            folderSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.midi]) { result in
            switch result {
            case .success(let url): importScoreFile(at: url)
            case .failure(let error): actionError = "\(error)"
            }
        }
        // Drag & drop straight from Finder/Files, same convention as SoundLibraryView's
        // soundfont import — every dropped item goes through the exact same
        // `importScoreFile(at:)` path as `.fileImporter`.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { importScoreFile(at: url) }
                }
            }
            return !providers.isEmpty
        }
    }

    // MARK: - Score import

    /// Only `.mid`/`.midi` can be imported so far — MusicXML/MuseScore are a later phase of the
    /// score-import feature (see the project plan). Mirrors `SoundLibraryView.importFile`'s own
    /// shape: yield once so the spinner actually paints, then run the (synchronous, main-actor)
    /// import on this thread since `ImprovSession` is thread-confined to wherever it was created.
    private func importScoreFile(at url: URL) {
        guard !isImporting else { return }
        isImporting = true
        Task {
            await Task.yield()
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
                isImporting = false
            }
            do {
                try session.importScore(at: url)
                onLoaded()
            } catch {
                actionError = "\(error)"
            }
        }
    }

    @ViewBuilder
    private var pieceSection: some View {
        Section {
            if let piece = session.piece {
                Text(piece.title).font(.headline)
                Text(L10n.string(.appFormatFragmentsBPM, session.currentLanguage, "\(piece.fragments.count)", String(format: "%.0f", piece.tempoBPM)))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(L10n.string(.appPlaceholderAucunMorceauChargePoint, session.currentLanguage)).foregroundStyle(.secondary)
            }
            Button(L10n.string(.appButtonChargerLaDemo, session.currentLanguage)) {
                session.loadDemoPiece()
                onLoaded()
            }
            Button {
                showFileImporter = true
            } label: {
                if isImporting {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                } else {
                    Label(L10n.string(.appButtonImporter, session.currentLanguage), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isImporting)
        } header: {
            Text(L10n.string(.appHeadingMorceauCharge, session.currentLanguage))
        }
    }

    @ViewBuilder
    private var folderSection: some View {
        Section {
            if session.pieceNames.isEmpty {
                Text(L10n.string(.appPlaceholderAucunDossierMorceaux, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(session.pieceNames.enumerated()), id: \.offset) { index, name in
                    HStack {
                        Button(name) {
                            do {
                                try session.usePiece(named: name)
                                onLoaded()
                            } catch {
                                actionError = "\(error)"
                            }
                        }
                        Spacer()
                        Button {
                            do {
                                try session.deletePiece(atIndex: index)
                            } catch {
                                actionError = "\(error)"
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }
            }
            if session.piece != nil {
                Button(L10n.string(.appButtonSauvegarderDansCeDossier, session.currentLanguage)) {
                    do {
                        try session.savePiece(as: session.piece?.title ?? L10n.string(.appDefaultMorceauFilename, session.currentLanguage))
                    } catch {
                        actionError = "\(error)"
                    }
                }
            }
        } header: {
            Text(L10n.string(.appHeadingDossierMorceaux, session.currentLanguage))
        }
    }
}

#Preview {
    PiecesFileView(session: ImprovSession(), onLoaded: {})
}

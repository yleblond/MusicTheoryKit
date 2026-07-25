import SwiftUI
import AppCore

/// "Fichier" sub-tab of the Morceaux tab: which piece is loaded, the demo piece, and the
/// folder-based piece browser (list/load/save-into-folder). Playback lives in the "Play"
/// sub-tab.
struct PiecesFileView: View {
    let session: ImprovSession
    /// Called after a piece is actually loaded (demo or from the folder) — `PiecesView`
    /// switches to the "Play" sub-tab, per explicit user request.
    let onLoaded: () -> Void

    @State private var actionError: String?

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
    }

    @ViewBuilder
    private var pieceSection: some View {
        Section {
            if let piece = session.piece {
                Text(piece.title).font(.headline)
                Text("\(piece.fragments.count) fragment(s), \(String(format: "%.0f", piece.tempoBPM)) BPM")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Aucun morceau charge.").foregroundStyle(.secondary)
            }
            Button("Charger la demo") {
                session.loadDemoPiece()
                onLoaded()
            }
        } header: {
            Text("Morceau charge")
        }
    }

    @ViewBuilder
    private var folderSection: some View {
        Section {
            if session.pieceFiles.isEmpty {
                Text("Aucun dossier de morceaux choisi — JamShack > Dossiers.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(session.pieceFiles, id: \.self) { name in
                    Button(name) {
                        do {
                            try session.loadPiece(named: name)
                            onLoaded()
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
                if session.piece != nil {
                    Button("Sauvegarder dans ce dossier") {
                        do {
                            try session.savePiece(as: (session.piece?.title ?? "Morceau") + ".json")
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
            }
        } header: {
            Text("Dossier de morceaux")
        }
    }
}

#Preview {
    PiecesFileView(session: ImprovSession(), onLoaded: {})
}

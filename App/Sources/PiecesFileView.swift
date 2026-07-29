import SwiftUI
import AppCore
import Localization

/// "Fichier" sub-tab of the Morceaux tab: which piece is loaded, the demo piece, and the
/// store-based piece browser (list/load/save/delete — pieces live in a private SwiftData
/// store, no folder to pick anymore). Playback lives in the "Play" sub-tab.
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
                Text(L10n.string(.appFormatFragmentsBPM, session.currentLanguage, "\(piece.fragments.count)", String(format: "%.0f", piece.tempoBPM)))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(L10n.string(.appPlaceholderAucunMorceauChargePoint, session.currentLanguage)).foregroundStyle(.secondary)
            }
            Button(L10n.string(.appButtonChargerLaDemo, session.currentLanguage)) {
                session.loadDemoPiece()
                onLoaded()
            }
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

import SwiftUI
import AppCore

/// The "Morceaux" tab — split into two sub-tabs: **Fichier** (loaded piece info, demo, folder
/// browser — loading a piece here switches to **Play** — see `PiecesFileView`) and **Play**
/// (play/stop the loaded piece, choose its sound — see `PiecesPlayView`).
struct PiecesView: View {
    let session: ImprovSession

    private enum SubTab: CaseIterable, Identifiable {
        case file, play

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .file: return "doc.text"
            case .play: return "play.fill"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .file: return "Fichier de morceau"
            case .play: return "Jouer"
            }
        }
    }

    @State private var subTab: SubTab = .file

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                ForEach(SubTab.allCases) { tab in
                    Button {
                        subTab = tab
                    } label: {
                        Image(systemName: tab.systemImage)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(
                                subTab == tab ? Color.accentColor.opacity(0.2) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.accessibilityLabel)
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            Divider()
            Group {
                switch subTab {
                case .file: PiecesFileView(session: session, onLoaded: { subTab = .play })
                case .play: PiecesPlayView(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    PiecesView(session: ImprovSession())
}

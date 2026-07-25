import SwiftUI
import AppCore
import JamShackUI

/// The "Guide" tab — split into three sub-tabs (same vertical icon-sidebar pattern as
/// "Scene"/"JamShack"): **Fichier** (create/load/save a guide sequence — see `GuideFileView`),
/// **Edition** (add a mode step, see the step list — see `GuideEditionView`), and **Lecture**
/// (start/stop, step/chord navigation incl. arrow keys, the live keyboard — see
/// `GuideLectureView`).
struct GuideView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    private enum SubTab: CaseIterable, Identifiable {
        case file, edition, lecture

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .file: return "doc.text"
            case .edition: return "pencil"
            case .lecture: return "play.fill"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .file: return "Fichier de guide"
            case .edition: return "Edition du guide"
            case .lecture: return "Lecture du guide"
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
                case .file: GuideFileView(session: session, onLoaded: { subTab = .lecture })
                case .edition: GuideEditionView(session: session, bridge: bridge)
                case .lecture: GuideLectureView(session: session, bridge: bridge)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    let session = ImprovSession()
    return GuideView(session: session, bridge: SessionUIBridge(session: session))
}

import SwiftUI
import AppCore
import JamShackUI
import Localization

/// The "Enregistrement" tab — split into four sub-tabs: **Fichier** (soundtrack folder —
/// loading one here switches to **Play** — see `RecordingFileView`), **Record** (source
/// selection, start/stop the recording — see `RecordingRecordView`), **Play** (play/stop the
/// current recording, choose its sound — see `RecordingPlayView`), and **IA** (compose a piece
/// from the recording — see `RecordingIAView`).
struct RecordingView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    private enum SubTab: CaseIterable, Identifiable {
        case file, record, play, ia

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .file: return "doc.text"
            case .record: return "record.circle"
            case .play: return "play.fill"
            case .ia: return "brain"
            }
        }

        func accessibilityLabel(_ language: AppLanguage) -> String {
            switch self {
            case .file: return L10n.string(.appTabFichierSoundtrack, language)
            case .record: return L10n.string(.catEnregistrement, language)
            case .play: return L10n.string(.appHeadingJouer, language)
            case .ia: return L10n.string(.appHeadingCompositionIA, language)
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
                    .accessibilityLabel(tab.accessibilityLabel(session.currentLanguage))
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            Divider()
            Group {
                switch subTab {
                case .file: RecordingFileView(session: session, onLoaded: { subTab = .play })
                case .record: RecordingRecordView(session: session, bridge: bridge)
                case .play: RecordingPlayView(session: session)
                case .ia: RecordingIAView(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    let session = ImprovSession()
    return RecordingView(session: session, bridge: SessionUIBridge(session: session))
}

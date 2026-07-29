import SwiftUI
import AppCore
import Localization

/// The "Enregistrements" tab — split out from `StudioView` (which used to hold these three
/// sub-tabs alongside Live/Scene/Guide): **Fichier** (`RecordingFileView` — the store-based
/// soundtrack browser), **Enregistrement actuel** (`RecordingPlayView` — play/stop the current
/// recording), and **Composition IA** (`RecordingIAView` — compose a piece from it via the
/// active LLM connection). None of these three need `bridge` — only `session`.
struct RecordingsView: View {
    let session: ImprovSession

    private enum SubTab: CaseIterable, Identifiable {
        case files, currentRecording, ia

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .files: return "doc.text"
            case .currentRecording: return "play.fill"
            case .ia: return "brain"
            }
        }

        func accessibilityLabel(_ language: AppLanguage) -> String {
            switch self {
            case .files: return L10n.string(.appTabFichierSoundtrack, language)
            case .currentRecording: return L10n.string(.appHeadingEnregistrementActuel, language)
            case .ia: return L10n.string(.appHeadingCompositionIA, language)
            }
        }
    }

    @State private var subTab: SubTab = .files

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
                case .files:
                    RecordingFileView(session: session, onLoaded: { subTab = .currentRecording })
                case .currentRecording:
                    RecordingPlayView(session: session)
                case .ia:
                    RecordingIAView(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    RecordingsView(session: ImprovSession())
}

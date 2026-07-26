import SwiftUI
import AppCore
import JamShackUI
import Localization

/// The "Studio" tab (renamed from "Live", 2026-07-26) — merges the former standalone
/// "Enregistrement" tab in here, since recording is something you do WHILE playing live, not a
/// separate destination. Four sub-tabs: **Live** (`RunScreen`, now with a "Demarrer
/// l'enregistrement" button — captures whichever tracks are currently listening, no manual
/// track-selection step, see `RunScreen`'s own doc comment), **Dossiers de soundtracks**
/// (`RecordingFileView`, unchanged), **Enregistrement actuel** (`RecordingPlayView` — sound
/// choice removed, now derived from the active scene automatically), and **Composer IA**
/// (`RecordingIAView`, unchanged).
struct StudioView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    private enum SubTab: CaseIterable, Identifiable {
        case live, soundtrackFiles, currentRecording, ia

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .live: return "pianokeys"
            case .soundtrackFiles: return "doc.text"
            case .currentRecording: return "play.fill"
            case .ia: return "brain"
            }
        }

        func accessibilityLabel(_ language: AppLanguage) -> String {
            switch self {
            case .live: return L10n.string(.appTabStudio, language)
            case .soundtrackFiles: return L10n.string(.appTabFichierSoundtrack, language)
            case .currentRecording: return L10n.string(.appHeadingEnregistrementActuel, language)
            case .ia: return L10n.string(.appHeadingCompositionIA, language)
            }
        }
    }

    @State private var subTab: SubTab = .live

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
                case .live:
                    RunScreen(
                        session: session,
                        bridge: bridge,
                        interactiveTrackID: TrackID.computerKeyboard.wireIDText,
                        onNoteOn: { pitch in session.pressKey(pitch: pitch) },
                        onNoteOff: { pitch in session.releaseKey(pitch: pitch) }
                    )
                    // Same LUMI-follows-the-active-screen wiring as Guide > Lecture.
                    .onAppear { session.notifyActiveScreen(.run) }
                    .onDisappear { session.notifyActiveScreen(.other) }
                case .soundtrackFiles:
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
    let session = ImprovSession()
    return StudioView(session: session, bridge: SessionUIBridge(session: session))
}

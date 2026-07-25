import SwiftUI
import AppCore
import JamShackUI

/// The "JamShack" tab — the GUI counterpart of the CLI's top-level `catJamShack` menu
/// category, grouped into sub-tabs the same way that menu grouped its own entries:
/// 1. **Dossiers**: every folder the app needs (pieces/samples/soundtracks/guides/scenes/
///    reglages/composition IA) — see `JamShackFoldersView`.
/// 2. **MIDI**: fusion mode, refresh, visible source list, live notes — see `JamShackMIDIView`.
/// 3. **Microphone**: start/stop the microphone track, level meter, live notes — see
///    `MicrophoneControlsView`.
/// 4. **Jam Session**: the collaborative server/client mode — see `JamSessionView`.
/// 5. **Serveurs**: the web console + virtual keyboard HTTP servers — see `ServerControlsView`.
/// 6. **Couleurs**: active color palette + LUMI Keys settings — see `JamShackColorsView`.
/// 7. **Langue**: UI language — see `JamShackLanguageView`.
/// 8. **LLM**: active LLM connection + a quick test call — see `JamShackLLMView`.
///
/// A vertical strip of icon-only buttons (a "sidebar" tab bar) rather than a horizontal
/// segmented control — 8 entries don't fit comfortably as horizontal text labels on an
/// iPhone-width screen without truncation, and icon-only avoids that entirely regardless of
/// width.
struct JamShackView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    private enum SubTab: CaseIterable, Identifiable {
        case dossiers, midi, microphone, jamSession, serveurs, couleurs, langue, llm

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .dossiers: return "folder"
            case .midi: return "pianokeys"
            case .microphone: return "mic"
            case .jamSession: return "person.2.fill"
            case .serveurs: return "server.rack"
            case .couleurs: return "paintpalette"
            case .langue: return "globe"
            case .llm: return "brain"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .dossiers: return "Dossiers"
            case .midi: return "MIDI"
            case .microphone: return "Microphone"
            case .jamSession: return "Jam Session"
            case .serveurs: return "Serveurs"
            case .couleurs: return "Couleurs"
            case .langue: return "Langue"
            case .llm: return "LLM"
            }
        }
    }

    @State private var subTab: SubTab = .dossiers

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
                case .dossiers: JamShackFoldersView(session: session)
                case .midi: JamShackMIDIView(session: session, bridge: bridge)
                case .microphone: MicrophoneControlsView(session: session, bridge: bridge)
                case .jamSession: JamSessionView(session: session)
                case .serveurs: ServerControlsView(session: session)
                case .couleurs: JamShackColorsView(session: session)
                case .langue: JamShackLanguageView(session: session)
                case .llm: JamShackLLMView(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    let session = ImprovSession()
    return JamShackView(session: session, bridge: SessionUIBridge(session: session))
}

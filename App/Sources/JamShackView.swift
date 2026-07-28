import SwiftUI
import AppCore
import JamShackUI
import Localization

/// The "JamShack" tab — the GUI counterpart of the CLI's top-level `catJamShack` menu
/// category, grouped into sub-tabs, ordered per explicit user request (2026-07-26):
/// 1. **Sons**: alias + favori per fichier son trouve dans le dossier "Sons (samples)" — see
///    `SoundsView`. Le dossier lui-meme peut contenir des sous-dossiers (ex: une librairie
///    decompressee avec plusieurs .sf2) — `favoriteSampleFiles` (les favoris marques ici) est
///    ce que tout autre picker de son (Morceaux/Enregistrement/Scenes) affiche ensuite, pour
///    ne pas noyer ces pickers dans une grosse librairie non triee.
/// 2. **Clavier ordinateur**: on/off switch for physical-keyboard note input, off by default —
///    see `ComputerKeyboardSettingsView`/`ImprovSession.computerKeyboardInputEnabled`.
/// 3. **MIDI** (clavier MIDI): fusion mode, refresh, visible source list, live notes — see
///    `JamShackMIDIView`.
/// 4. **Microphone**: start/stop the microphone track, level meter, live notes — see
///    `MicrophoneControlsView`.
/// 5. **Jam Session**: the two HTTP servers (console web, clavier virtuel — "Own devices") and
///    the collaborative server/client mode ("Connected devices") — see `JamSessionView`, merged
///    from what used to be two separate sub-tabs (2026-07-26).
/// 6. **Couleurs**: active color palette + LUMI Keys settings — see `JamShackColorsView`.
/// 7. **LLM**: active LLM connection + a quick test call — see `JamShackLLMView`.
/// 8. **Dossiers**: every folder the app needs (pieces/samples/soundtracks/guides/scenes/
///    reglages/composition IA) — see `JamShackFoldersView`.
/// 9. **Langue**: UI language — see `JamShackLanguageView`.
///
/// A vertical strip of icon-only buttons (a "sidebar" tab bar) rather than a horizontal
/// segmented control — this many entries don't fit comfortably as horizontal text labels on an
/// iPhone-width screen without truncation, and icon-only avoids that entirely regardless of
/// width.
struct JamShackView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge
    /// Whether the "JamShack" tab itself is the one currently selected in `ContentView` —
    /// threaded down to `SoundsView` (combined with this view's own `subTab == .sons`) so it
    /// can reliably tell when it's truly no longer visible. See `SoundsView`'s own doc comment
    /// on why `.onDisappear` alone isn't enough for that.
    let isActiveTab: Bool

    private enum SubTab: CaseIterable, Identifiable {
        case sons, clavierOrdinateur, midi, microphone, jamSession, couleurs, llm, dossiers, langue

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .sons: return "music.note.list"
            case .clavierOrdinateur: return "keyboard"
            case .midi: return "pianokeys"
            case .microphone: return "mic"
            case .jamSession: return "person.2.fill"
            case .couleurs: return "paintpalette"
            case .llm: return "brain"
            case .dossiers: return "folder"
            case .langue: return "globe"
            }
        }

        func accessibilityLabel(_ language: AppLanguage) -> String {
            switch self {
            case .sons: return L10n.string(.appTabSons, language)
            case .clavierOrdinateur: return L10n.string(.appTabClavierOrdinateur, language)
            case .midi: return L10n.string(.appTabMIDI, language)
            case .microphone: return L10n.string(.appTabMicrophone, language)
            case .jamSession: return L10n.string(.catJamSession, language)
            case .couleurs: return L10n.string(.appTabCouleurs, language)
            case .llm: return L10n.string(.appTabLLM, language)
            case .dossiers: return L10n.string(.appTabDossiers, language)
            case .langue: return L10n.string(.appTabLangue, language)
            }
        }
    }

    @State private var subTab: SubTab = .sons

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
                case .sons: SoundsView(session: session, bridge: bridge, isActive: isActiveTab && subTab == .sons)
                case .clavierOrdinateur: ComputerKeyboardSettingsView(session: session)
                case .midi: JamShackMIDIView(session: session, bridge: bridge)
                case .microphone: MicrophoneControlsView(session: session, bridge: bridge)
                case .jamSession: JamSessionView(session: session)
                case .couleurs: JamShackColorsView(session: session)
                case .llm: JamShackLLMView(session: session)
                case .dossiers: JamShackFoldersView(session: session)
                case .langue: JamShackLanguageView(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    let session = ImprovSession()
    return JamShackView(session: session, bridge: SessionUIBridge(session: session), isActiveTab: true)
}

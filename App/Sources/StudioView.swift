import SwiftUI
import AppCore
import JamShackUI
import Localization

/// The "Studio" tab — where you set up and play, three sub-tabs: **Live** (`RunScreen`, "where
/// you see yourself playing" — circle-of-fifths wheel, per-track live keyboards, the "Demarrer
/// l'enregistrement" button), **Scene** (`SceneManagementView` — which instrument sounds through
/// which role), and **Guide** (`GuideView` — mode sequences to practice/perform against).
/// Scene and Guide used to be their own top-level tabs; folded in here (alongside Live) since
/// all three are facets of "what you're actively performing with right now." Each keeps its own
/// internal navigation unchanged (Scene/Guide's own list -> configuration flow) — this is purely
/// about which container they're mounted in. What used to be Studio's other three sub-tabs
/// (recordings list/playback/IA composition) moved out to the new top-level "Enregistrements"
/// tab — see `RecordingsView`.
struct StudioView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    private enum SubTab: CaseIterable, Identifiable {
        case live, scene, guide

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .live: return "pianokeys"
            case .scene: return "theatermasks"
            case .guide: return "map"
            }
        }

        func accessibilityLabel(_ language: AppLanguage) -> String {
            switch self {
            case .live: return L10n.string(.appTabStudio, language)
            case .scene: return L10n.string(.tabScene, language)
            case .guide: return L10n.string(.headingGuide, language)
            }
        }
    }

    // Defaults to Scene, not Live — same "land on the setup screen" rationale the old
    // standalone Scene tab used to have as the app's own default landing tab.
    @State private var subTab: SubTab = .scene

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
                    RunScreen(session: session, bridge: bridge)
                    // Same LUMI-follows-the-active-screen wiring as Guide > Lecture.
                    .onAppear { session.notifyActiveScreen(.run) }
                    .onDisappear { session.notifyActiveScreen(.other) }
                case .scene:
                    SceneManagementView(session: session)
                case .guide:
                    GuideView(session: session, bridge: bridge)
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

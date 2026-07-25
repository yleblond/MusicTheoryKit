import SwiftUI
import AppCore

/// The "Composition" tab — split into two sub-tabs: **Fichier** (composition-description
/// folder — see `CompositionFileView`) and **Composer** (title/style/description + the
/// compose action — see `CompositionComposerView`).
struct CompositionView: View {
    let session: ImprovSession

    private enum SubTab: CaseIterable, Identifiable {
        case file, composer

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .file: return "doc.text"
            case .composer: return "wand.and.stars"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .file: return "Fichier de composition"
            case .composer: return "Composer"
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
                case .file: CompositionFileView(session: session)
                case .composer: CompositionComposerView(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    CompositionView(session: ImprovSession())
}

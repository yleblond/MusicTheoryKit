import SwiftUI
import AppCore
import JamShackUI
import Localization

/// "Théorie" settings tab — currently just which sound the Accords/Modes/Progressions tabs use
/// for audition playback (moved out of those screens' own header, per explicit request, since
/// it's a single shared choice rather than something worth re-picking from every screen). Will
/// also host per-role color customization for those same screens once that's built (see
/// `Docs/BACKLOG_BRUT.md`).
struct TheorieSettingsView: View {
    let session: ImprovSession

    @State private var actionError: String?

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            Section {
                FavoriteSoundPickerView(
                    favoriteSounds: session.favoriteSounds,
                    selectedID: Binding(
                        get: { session.theoryAuditionSoundID },
                        set: { newValue in
                            do {
                                try session.setTheoryAuditionSoundID(newValue)
                            } catch {
                                actionError = "\(error)"
                            }
                        }
                    ),
                    language: session.currentLanguage
                )
            } header: {
                Text(L10n.string(.appHeadingSonAudition, session.currentLanguage))
            } footer: {
                Text(L10n.string(.appHintSonAuditionTheorie, session.currentLanguage))
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }
}

#Preview {
    TheorieSettingsView(session: ImprovSession())
}

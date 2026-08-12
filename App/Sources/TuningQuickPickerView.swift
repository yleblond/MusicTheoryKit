import SwiftUI
import AppCore
import MusicTheoryKit
import Localization

/// The bottom bar's tuning-fork button popover — lets the temperament + A4 reference
/// (`ImprovSession.tuningConfiguration`) be changed from any Théorie tab without navigating to
/// the Intonations screen, per explicit request. Deliberately does NOT also offer a tonic/mode
/// picker: `TuningConfiguration` itself has no such field (it's just `temperamentID`/
/// `referenceA4`) — the tonic/mode shown underneath the tuning-fork button is Intonations' own
/// separate local exploration state (`TuningLibraryView.selectedTonic`/`selectedScaleID`), not
/// something this global setting is anchored to, so bundling a mode picker in here would imply a
/// coupling that doesn't actually exist. Intonations itself keeps exploring the impact of a
/// tonic/mode pick exactly as before — this popover only ever touches the temperament/A4 half.
struct TuningQuickPickerView: View {
    let session: ImprovSession

    @State private var referenceA4Text: String = ""
    @State private var actionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string(.appFieldTemperament, session.currentLanguage)).font(.headline)
            Picker(L10n.string(.appFieldTemperament, session.currentLanguage), selection: Binding(
                get: { session.tuningConfiguration.temperamentID },
                set: { newID in updateConfiguration { $0.temperamentID = newID } }
            )) {
                ForEach(TemperamentLibrary.all) { temperament in
                    Text(label(forTemperamentID: temperament.id)).tag(temperament.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            HStack {
                Text(L10n.string(.appFieldReferenceA4, session.currentLanguage))
                TextField("440", text: $referenceA4Text)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .onSubmit(commitReferenceA4)
                    #if os(macOS)
                    .onChange(of: referenceA4Text) { _, _ in commitReferenceA4() }
                    #endif
            }

            if let actionError {
                Text(actionError).foregroundStyle(.red).font(.caption)
            }
        }
        .padding()
        .frame(minWidth: 220)
        .onAppear { referenceA4Text = formattedA4(session.tuningConfiguration.referenceA4) }
    }

    /// Same id → display-name mapping `TuningLibraryView.label(forTemperamentID:)`/
    /// `ContentView.temperamentLabel(forID:language:)` use — duplicated rather than shared per
    /// this project's own established convention for this exact 4-id mapping (see either of
    /// those two's own doc comment).
    private func label(forTemperamentID id: String) -> String {
        switch id {
        case "equal": return L10n.string(.appTemperamentEqual, session.currentLanguage)
        case "pythagorean": return L10n.string(.appTemperamentPythagorean, session.currentLanguage)
        case "justIntonation": return L10n.string(.appTemperamentJustIntonation, session.currentLanguage)
        case "werckmeisterIII": return L10n.string(.appTemperamentWerckmeisterIII, session.currentLanguage)
        default: return id
        }
    }

    private func formattedA4(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }

    private func commitReferenceA4() {
        guard let value = Double(referenceA4Text.replacingOccurrences(of: ",", with: ".")), value > 0 else { return }
        updateConfiguration { $0.referenceA4 = value }
    }

    private func updateConfiguration(_ mutate: (inout TuningConfiguration) -> Void) {
        var configuration = session.tuningConfiguration
        mutate(&configuration)
        do {
            try session.setTuningConfiguration(configuration)
        } catch {
            actionError = "\(error)"
        }
    }
}

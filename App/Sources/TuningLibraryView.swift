import SwiftUI
import AppCore
import MusicTheoryKit
import Localization

/// Théorie's "Intonations" tab — picks a fixed temperament + A4 reference (`TuningConfiguration`,
/// persisted via `session.setTuningConfiguration(_:)`, same pattern as `NotationStyleSettingsView`).
/// The TONIC the temperament is anchored to is deliberately NOT picked here — it's read-only,
/// derived from whichever of Modes/Progressions/Exploration last had its own tonic/mode active
/// (`session.contextualTonic`, set by those screens themselves) — a fixed temperament has nothing
/// to anchor to on Accords/Tonnetz, which only ever have a bare chord/note, never a tonic (see
/// this feature's own plan for why only a future per-chord *dynamic* tuning would fit there).
struct TuningLibraryView: View {
    let session: ImprovSession

    @State private var actionError: String?
    @State private var referenceA4Text: String = ""

    private var sourceID: TrackID? { session.theoryLiveInputSourceID }

    private var heldPitches: [Int] {
        guard let sourceID else { return [] }
        return (session.tracks.first { $0.id == sourceID }?.heldPitches ?? []).sorted()
    }

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }

            Section {
                Picker(L10n.string(.appFieldTemperament, session.currentLanguage), selection: Binding(
                    get: { session.tuningConfiguration.temperamentID },
                    set: { newID in updateConfiguration { $0.temperamentID = newID } }
                )) {
                    ForEach(TemperamentLibrary.all) { temperament in
                        Text(label(forTemperamentID: temperament.id)).tag(temperament.id)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text(L10n.string(.appFieldReferenceA4, session.currentLanguage))
                    Spacer()
                    TextField("440", text: $referenceA4Text)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onSubmit(commitReferenceA4)
                        #if os(macOS)
                        .onChange(of: referenceA4Text) { _, _ in commitReferenceA4() }
                        #endif
                }
            } header: {
                Text(L10n.string(.appTabIntonations, session.currentLanguage))
            }

            Section {
                if let contextualTonic = session.contextualTonic {
                    Text(session.notationStyle.rootName(contextualTonic, preferFlats: false))
                        .font(.title2).bold()
                } else {
                    Text(L10n.string(.appHintAucunModeActifIntonations, session.currentLanguage))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.string(.appLabelToniqueActuelle, session.currentLanguage))
            }

            if let contextualTonic = session.contextualTonic, !heldPitches.isEmpty {
                Section {
                    ForEach(heldPitches, id: \.self) { pitch in
                        let cents = fixedTemperamentCents(forPitchClass: PitchClass(pitch), tonic: contextualTonic, configuration: session.tuningConfiguration)
                        HStack {
                            Text(session.notationStyle.rootName(PitchClass(pitch), preferFlats: false))
                            Spacer()
                            Text(String(format: "%+.1f ¢", cents)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                } header: {
                    Text(L10n.string(.appHeadingNotesTenuesEtCorrection, session.currentLanguage))
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .onAppear { referenceA4Text = formattedA4(session.tuningConfiguration.referenceA4) }
    }

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

#Preview {
    TuningLibraryView(session: ImprovSession())
}

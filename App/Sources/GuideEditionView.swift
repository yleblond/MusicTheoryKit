import SwiftUI
import AppCore
import MusicTheoryKit
import PieceModel
import JamShackUI
import Localization
import SoundFontModel

/// Edition mode of the Guide tab's screen 2 (`GuideConfigurationView`): add a mode step to the
/// active guide, and see the current step list — structural editing, as opposed to Lecture
/// mode's playback controls. Only ever shown with a guide already active (screen 2 guarantees
/// it), so no "no active guide" fallback UI here.
struct GuideEditionView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge
    /// Switches the parent `GuideConfigurationView` to its Lecture mode — same ad hoc callback
    /// pattern already used by `GuideFileView`'s own `onLoaded`.
    let onRequestLecture: () -> Void

    @State private var selectedTonic = 0
    @State private var selectedScaleID = ScaleLibrary.all[0].id
    @State private var selectedProgressionName: String?
    @State private var actionError: String?
    @State private var auditionSampleID: String?
    @State private var auditionSpeed: Double = 1.0

    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            addStepSection
            GuideStepsSection(session: session, bridge: bridge)
            Section {
                Button(L10n.string(.appButtonVoirLeGuide, session.currentLanguage), action: onRequestLecture)
            }
            listenSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    @ViewBuilder
    private var addStepSection: some View {
        Section {
            Picker(L10n.string(.fieldTonique, session.currentLanguage), selection: $selectedTonic) {
                ForEach(0..<12, id: \.self) { pitchClass in Text(Self.noteNames[pitchClass]).tag(pitchClass) }
            }
            Picker(L10n.string(.fieldGamme, session.currentLanguage), selection: $selectedScaleID) {
                ForEach(ScaleLibrary.all, id: \.id) { scale in
                    Text("\(scale.popularName) (\(scale.systematicName))").tag(scale.id)
                }
            }
            Picker(L10n.string(.appFieldProgressionAccordsGuide, session.currentLanguage), selection: $selectedProgressionName) {
                Text(L10n.string(.appOptionAucuneFem, session.currentLanguage)).tag(String?.none)
                ForEach(session.chordProgressionTemplates, id: \.name) { template in
                    Text(template.name).tag(String?.some(template.name))
                }
            }
            Button(L10n.string(.appButtonAjouterModeAuGuide, session.currentLanguage)) {
                let template = selectedProgressionName.flatMap { name in
                    session.chordProgressionTemplates.first { $0.name == name }
                }
                do {
                    try session.addGuideStep(ModeReference(tonic: selectedTonic, scaleID: selectedScaleID), chordProgression: template)
                } catch {
                    actionError = "\(error)"
                }
            }
        } header: {
            Text(L10n.string(.appHeadingAjouterUnMode, session.currentLanguage))
        }
    }

    /// Plays the active guide's steps audibly through `ImprovSession.startGuideAudition(speedFactor:)`
    /// — a chord-hold per chord (or tonic alone for a step with no progression), no melody/timing
    /// beyond the flat per-chord duration `auditionSpeed` scales (a guide has no tempo of its own).
    @ViewBuilder
    private var listenSection: some View {
        Section {
            if session.favoriteSounds.isEmpty {
                Text(L10n.string(.appPlaceholderAucunSonFavori, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
            } else {
                Picker(L10n.string(.fieldSon, session.currentLanguage), selection: $auditionSampleID) {
                    Text(L10n.string(.appButtonAucun, session.currentLanguage)).tag(String?.none)
                    ForEach(session.favoriteSounds) { sound in
                        Text(sound.displayName).tag(String?.some(sound.id))
                    }
                }
            }
            VStack(alignment: .leading) {
                Text("\(L10n.string(.appFieldVitesse, session.currentLanguage)) : ×\(String(format: "%.2f", auditionSpeed))")
                Slider(value: $auditionSpeed, in: 0.25...3, step: 0.25)
            }
            if session.isAuditioningGuide {
                Button(L10n.string(.appButtonArreter, session.currentLanguage), role: .destructive) {
                    session.stopGuideAudition()
                }
            } else {
                Button(L10n.string(.appButtonDemarrer, session.currentLanguage)) {
                    if let sound = session.favoriteSounds.first(where: { $0.id == auditionSampleID }) {
                        try? session.loadGuideAuditionSample(named: sound.path, preset: sound.preset)
                    }
                    session.startGuideAudition(speedFactor: auditionSpeed)
                }
            }
        } header: {
            Text(L10n.string(.appHeadingEcouterLeGuide, session.currentLanguage))
        }
    }
}

#Preview {
    let session = ImprovSession()
    return GuideEditionView(session: session, bridge: SessionUIBridge(session: session), onRequestLecture: {})
}

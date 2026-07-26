import SwiftUI
import AppCore
import MusicTheoryKit
import PieceModel
import JamShackUI
import Localization

/// "Edition" sub-tab of the Guide tab: add a mode step to the active guide, and see the
/// current step list — structural editing, as opposed to the "Lecture" sub-tab's playback
/// controls.
struct GuideEditionView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    @State private var selectedTonic = 0
    @State private var selectedScaleID = ScaleLibrary.all[0].id
    @State private var selectedProgressionName: String?
    @State private var actionError: String?

    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            if session.currentGuide != nil {
                addStepSection
                GuideStepsSection(session: session, bridge: bridge)
            } else {
                Section {
                    Text(L10n.string(.appPlaceholderAucunGuideActif, session.currentLanguage)).foregroundStyle(.secondary)
                    ActivateOrCreateBlock(
                        files: session.guideFiles,
                        onActivate: { try session.loadGuideSequence(named: $0) },
                        createButtonLabel: L10n.string(.appButtonCreerUnGuide, session.currentLanguage),
                        createAlertTitle: L10n.string(.appNouveauGuide, session.currentLanguage),
                        createFieldPlaceholder: L10n.string(.appFieldTitreGuide, session.currentLanguage),
                        onCreate: { session.newGuideSequence(title: $0) },
                        language: session.currentLanguage
                    )
                }
            }
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
}

#Preview {
    let session = ImprovSession()
    return GuideEditionView(session: session, bridge: SessionUIBridge(session: session))
}

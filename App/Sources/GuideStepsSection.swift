import SwiftUI
import AppCore
import MusicTheoryKit
import PieceModel
import JamShackUI
import Localization

/// The guide's step list — shared by the "Edition" (structural) and "Lecture" (playback)
/// sub-tabs of the Guide tab, so the exact same rendering (including which step is currently
/// playing) never has two copies to keep in sync.
///
/// Each step with a chord progression expands (`DisclosureGroup`) to show every chord, dual
/// labeled — the roman-numeral degree the progression template was written in (re-derived from
/// `session.chordProgressionTemplates` by `chordProgressionName`, zipped by index with the
/// already-resolved `chordProgression` — the two line up as long as every token in the
/// template actually parsed, true for all built-in templates) alongside the real resolved chord
/// name (e.g. "I · Cmaj") — and a `Menu` per chord to change its quality (7th/sus/etc. on the
/// same root, `ChordVocabulary.allChords(forRoot:)`) without touching the rest of the
/// progression.
struct GuideStepsSection: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    @State private var actionError: String?
    /// Toggled by the "Reorganiser" button below rather than relying on a `NavigationStack`'s
    /// own `EditButton` — this screen has no navigation bar to host one (a plain `Form`, like
    /// every other sub-tab in this app), so the edit mode is switched locally, scoped to just
    /// this `Section`'s own rows via `.environment(\.editMode:)` below.
    @State private var isReordering = false

    var body: some View {
        Section {
            if let actionError {
                Text(actionError).font(.caption).foregroundStyle(.red)
            }
            ForEach(Array((session.currentGuide?.steps ?? []).enumerated()), id: \.offset) { index, step in
                DisclosureGroup {
                    chordRows(stepIndex: index, step: step)
                    progressionPicker(stepIndex: index, step: step)
                } label: {
                    stepLabel(index: index, step: step)
                }
            }
            .onMove { source, destination in
                do {
                    try session.moveGuideSteps(fromOffsets: source, toOffset: destination)
                } catch {
                    actionError = "\(error)"
                }
            }
            if (session.currentGuide?.steps ?? []).count > 1 {
                Button(isReordering ? L10n.string(.appButtonTerminerReorganisation, session.currentLanguage) : L10n.string(.appButtonReorganiser, session.currentLanguage)) {
                    isReordering.toggle()
                }
            }
        } header: {
            Text(L10n.string(.appHeadingEtapes, session.currentLanguage))
        }
        #if os(iOS)
        // macOS has no `EditMode` concept at all (`\.editMode` doesn't exist there) — its
        // `List`/`Form` already support direct drag-to-reorder via `.onMove` with no separate
        // edit-mode gate, so the "Reorganiser" toggle above only needs to actually drive
        // anything on iOS, where `.onMove` handles stay hidden until edit mode is active.
        .environment(\.editMode, .constant(isReordering ? .active : .inactive))
        #endif
    }

    @ViewBuilder
    private func stepLabel(index: Int, step: GuideStep) -> some View {
        HStack {
            Text("\(index + 1). \(step.mode.resolve()?.displayName ?? step.mode.scaleID)")
            if let name = step.chordProgressionName {
                Text("(\(name))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if index == bridge.state.guide?.currentStepIndex {
                Image(systemName: "play.fill").foregroundStyle(Color.accentColor)
            }
        }
    }

    /// Re-picks/changes an already-created step's chord progression — the "Ajouter un mode"
    /// picker in `GuideEditionView` only ever sets this at creation time; this is the same
    /// picker, reusable per existing step, calling `setGuideStepChordProgression(atIndex:template:)`
    /// instead of `addGuideStep`.
    @ViewBuilder
    private func progressionPicker(stepIndex: Int, step: GuideStep) -> some View {
        Picker(L10n.string(.appFieldProgressionAccordsGuide, session.currentLanguage), selection: Binding(
            get: { step.chordProgressionName },
            set: { newName in
                let template = newName.flatMap { name in session.chordProgressionTemplates.first { $0.name == name } }
                do {
                    try session.setGuideStepChordProgression(atIndex: stepIndex, template: template)
                } catch {
                    actionError = "\(error)"
                }
            }
        )) {
            Text(L10n.string(.appOptionAucuneFem, session.currentLanguage)).tag(String?.none)
            ForEach(session.chordProgressionTemplates, id: \.name) { template in
                Text(template.name).tag(String?.some(template.name))
            }
        }
    }

    @ViewBuilder
    private func chordRows(stepIndex: Int, step: GuideStep) -> some View {
        let romanTokens = session.chordProgressionTemplates.first(where: { $0.name == step.chordProgressionName })?.degrees ?? []
        ForEach(Array((step.chordProgression ?? []).enumerated()), id: \.offset) { chordIndex, chordReference in
            HStack {
                Text(romanTokens.indices.contains(chordIndex) ? romanTokens[chordIndex] : "?")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
                Menu(chordReference.resolve()?.displayName ?? "?") {
                    ForEach(ChordVocabulary.allChords(forRoot: PitchClass(chordReference.root)), id: \.template.id) { chord in
                        Button(chord.displayName) {
                            do {
                                try session.setGuideStepChordQuality(
                                    stepIndex: stepIndex, chordIndex: chordIndex, templateID: chord.template.id
                                )
                            } catch {
                                actionError = "\(error)"
                            }
                        }
                    }
                }
            }
        }
        .onMove { source, destination in
            do {
                try session.moveGuideStepChords(atStepIndex: stepIndex, fromOffsets: source, toOffset: destination)
            } catch {
                actionError = "\(error)"
            }
        }
    }
}

#Preview {
    let session = ImprovSession()
    return Form { GuideStepsSection(session: session, bridge: SessionUIBridge(session: session)) }
}

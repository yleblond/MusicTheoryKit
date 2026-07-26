import SwiftUI
import AppCore
import MusicTheoryKit
import PieceModel
import Localization

/// 2.a of the Guide "Lecture" screen: a flattened textual description of the whole guide —
/// every step's label on one line (the current one bracketed/bold) and the current step's
/// chord progression on a second line (the current chord bracketed/bold) — mirrors the web
/// console's own `renderGuide` text lines (`Sources/WebConsole/StaticAssets.swift`) as native
/// `Text` instead of HTML.
struct GuideDescriptionView: View {
    let guide: WebConsoleGuideState
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            stepsLine
            if !guide.currentChordProgression.isEmpty {
                progressionLine
            }
        }
    }

    private var stepsLine: Text {
        var line = Text("")
        for (index, step) in guide.steps.enumerated() {
            if index > 0 { line = line + Text(" ") }
            line = line + (step.isCurrent ? Text("[\(step.label)]").bold() : Text(step.label))
        }
        return line
    }

    private var progressionLine: Text {
        let prefix = guide.currentChordProgressionName.map { L10n.string(.appFormatSuiteAccordsPrefix, language, $0) } ?? L10n.string(.appLabelSuiteAccordsSansNom, language)
        var line = Text(prefix)
        for (index, entry) in guide.currentChordProgression.enumerated() {
            if index > 0 { line = line + Text(" - ") }
            line = line + (index == guide.currentChordIndex ? Text("[\(entry.label)]").bold() : Text(entry.label))
        }
        return line
    }
}

#Preview {
    // `WebConsoleGuideState` has no public initializer (see `WebConsoleState.swift`'s own
    // doc comment — only `ImprovSession` itself constructs these) — building one for a
    // preview goes through a real session's real API instead of faking one.
    let session = ImprovSession()
    session.newGuideSequence(title: L10n.string(.appDefaultGuideTitle, session.currentLanguage))
    try? session.addGuideStep(ModeReference(tonic: 0, scaleID: ScaleLibrary.all[0].id), chordProgression: session.chordProgressionTemplates.first)
    try? session.addGuideStep(ModeReference(tonic: 7, scaleID: ScaleLibrary.all[0].id))
    try? session.startGuide()
    session.advanceGuideChord(by: 1)
    let guide = session.buildWebConsoleState().guide!
    return GuideDescriptionView(guide: guide, language: session.currentLanguage).padding()
}

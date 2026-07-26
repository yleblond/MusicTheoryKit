import SwiftUI
import AppCore
import JamShackUI
import Localization

/// The guide's step list — shared by the "Edition" (structural) and "Lecture" (playback)
/// sub-tabs of the Guide tab, so the exact same rendering (including which step is currently
/// playing) never has two copies to keep in sync.
struct GuideStepsSection: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    var body: some View {
        Section {
            ForEach(Array((session.currentGuide?.steps ?? []).enumerated()), id: \.offset) { index, step in
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
        } header: {
            Text(L10n.string(.appHeadingEtapes, session.currentLanguage))
        }
    }
}

#Preview {
    let session = ImprovSession()
    return Form { GuideStepsSection(session: session, bridge: SessionUIBridge(session: session)) }
}

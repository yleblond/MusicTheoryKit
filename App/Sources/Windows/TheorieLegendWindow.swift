import SwiftUI
import JamShackUI

/// Root view of `AuxiliaryWindowID.theorieLegende`'s `WindowGroup` — a small, independent
/// window (macOS/visionOS) showing `TheoryLegendContent` on its own, so it can stay open
/// alongside the Modes/Accords screens while working rather than covering them like a popover
/// would. No open/closed tracking — see `AuxiliaryWindowID.theorieLegende`'s own doc comment.
struct TheorieLegendWindow: View {
    var body: some View {
        SessionGatedView { session, _ in
            ScrollView {
                TheoryLegendContent(language: session.currentLanguage)
                    .padding()
            }
        }
    }
}

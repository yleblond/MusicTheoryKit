import SwiftUI
import JamShackUI
import ScoreImport
import PieceModel
import Localization

/// Sheet content for "Voir la partition" (`PiecesPlayView`): renders the currently-loaded
/// `Piece` as real notation via `ScoreEngravingView`/VexFlow. No role-coloring/click actions
/// yet — this is the "brut"/plain rendering step; harmonic/melodic role coloring is a later
/// phase of the score-import feature (see the project plan).
struct PieceScoreSheet: View {
    let piece: Piece
    let language: AppLanguage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // No outer ScrollView: the WKWebView (score.html) already scrolls its own content
            // horizontally/vertically when it overflows this frame — nesting a SwiftUI
            // ScrollView around it risks gesture conflicts between the two scroll surfaces.
            ScoreEngravingView(score: ScoreEngravingAdapter.build(from: piece))
                .frame(minWidth: 600, minHeight: 300)
                .padding()
                .navigationTitle(L10n.string(.appHeadingPartition, language))
                #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.string(.appButtonFermer, language)) { dismiss() }
                    }
                }
        }
    }
}

#Preview {
    PieceScoreSheet(
        piece: Piece(title: "Aperçu", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian")),
        language: .fr
    )
}

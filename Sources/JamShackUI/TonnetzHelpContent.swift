import SwiftUI
import Localization

/// The prose explanation shown by `TheoryHelpButton`'s pop-up for the Tonnetz screen — same shape
/// as `FunctionalMapHelpContent`/`MelodicMapHelpContent` (title + `.callout` lines), with the
/// compact `TonnetzLegendView` embedded at the bottom so the pop-up has more substance than the
/// swatch key alone (already visible permanently in the Harmonic column).
public struct TonnetzHelpContent: View {
    public let language: AppLanguage

    public init(language: AppLanguage) {
        self.language = language
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string(.appHelpTonnetzTitle, language)).font(.headline)
            Group {
                Text(L10n.string(.appHelpTonnetzAxes, language))
                Text(L10n.string(.appHelpTonnetzTriangles, language))
                Text(L10n.string(.appHelpTonnetzGraphs, language))
                Text(L10n.string(.appHelpTonnetzDiatonic, language))
            }
            .font(.callout)
            Divider()
            TonnetzLegendView(language: language, axis: .horizontal)
        }
        .frame(maxWidth: 340, alignment: .leading)
    }
}

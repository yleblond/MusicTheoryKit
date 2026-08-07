import SwiftUI
import Localization

/// Everything explaining BOTH the harmonic (`FunctionalMapLegendView`) and melodic
/// (`MelodicMapLegendView`) color palettes, combined into one place — the two used to each have
/// their own "?" popover; per explicit request, every legend now lives in one real
/// window/sheet instead (`TheoryLegendWindow` on macOS/visionOS, a dismissible sheet on iOS —
/// both built in the App target, since only it can reach the platform windowing/`AuxiliaryWindowID`
/// machinery; this view is the shared, platform-agnostic content either one displays).
public struct TheoryLegendContent: View {
    public let language: AppLanguage

    public init(language: AppLanguage) {
        self.language = language
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FunctionalMapHelpContent(language: language)
            Divider()
            MelodicMapHelpContent(language: language)
        }
        .frame(maxWidth: 420, alignment: .leading)
    }
}

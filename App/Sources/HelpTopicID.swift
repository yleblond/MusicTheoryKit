import SwiftUI
import AppCore
import JamShackUI
import Localization

/// One case per top-level screen that has (or will have) its own contextual help — the currency
/// for `View.registerContextualHelp`'s `id:` parameter (raw value, e.g. `"theorie.tonnetz"` —
/// unchanged from the hand-typed string literal the two pre-existing screens already used, so
/// migrating them doesn't disturb `registerMainKeyboardMode`/`registerMainKeyboardChord`, which
/// reuse the very same id strings independently) AND for the custom-scheme cross-screen help
/// links `HelpContentView`'s authored markdown can contain (`[label](jamshackhelp://<rawValue>)`)
/// — see `View.interceptHelpLinks(pinnedTopic:)`. A `String`-backed `CaseIterable` enum rather
/// than a raw dictionary of content-closures: a `switch` in `content` below is exhaustive, so
/// adding a new screen without content is a compile error, not a silently-empty help window.
enum HelpTopicID: String, CaseIterable {
    case home
    case studioScene = "studio.scene"
    case studioLive = "studio.live"
    case studioGuide = "studio.guide"
    case studioRecordings = "studio.recordings"
    case studioJamSession = "studio.jamSession"
    case compositionGuide = "composition.guide"
    case compositionComposition = "composition.composition"
    case compositionPieces = "composition.pieces"
    case theorieAccords = "theorie.accords"
    case theorieModes = "theorie.modes"
    case theorieProgressions = "theorie.progressions"
    case theorieExploration = "theorie.exploration"
    case theorieTonnetz = "theorie.tonnetz"
    case theorieIntonations = "theorie.intonations"
    case theorieDissonances = "theorie.dissonances"
    case settingsSons = "settings.sons"
    case settingsMidi = "settings.midi"
    case settingsMicrophone = "settings.microphone"
    case settingsConsole = "settings.console"
    case settingsCouleurs = "settings.couleurs"
    case settingsLLM = "settings.llm"
    case settingsLangue = "settings.langue"
    case settingsNotation = "settings.notation"

    /// The rendered help content for this screen — `HelpContentView` handles markdown/fallback;
    /// this just supplies the (title key, body key) pair. `theorieTonnetz` and `compositionPieces`
    /// each add their own trailing live-component swatch (`TonnetzLegendView`/
    /// `ScoreColorLegendView`) instead of pure prose (see `HelpContentView`'s `trailing` slot).
    @ViewBuilder
    func content(language: AppLanguage) -> some View {
        switch self {
        case .home:
            HelpContentView(title: L10n.string(.appHelpHomeTitle, language), body: L10n.string(.appHelpHomeBody, language))
        case .studioScene:
            HelpContentView(title: L10n.string(.appHelpStudioSceneTitle, language), body: L10n.string(.appHelpStudioSceneBody, language))
        case .studioLive:
            HelpContentView(title: L10n.string(.appHelpStudioLiveTitle, language), body: L10n.string(.appHelpStudioLiveBody, language))
        case .studioGuide:
            HelpContentView(title: L10n.string(.appHelpStudioGuideTitle, language), body: L10n.string(.appHelpStudioGuideBody, language))
        case .studioRecordings:
            HelpContentView(title: L10n.string(.appHelpStudioRecordingsTitle, language), body: L10n.string(.appHelpStudioRecordingsBody, language))
        case .studioJamSession:
            HelpContentView(title: L10n.string(.appHelpStudioJamSessionTitle, language), body: L10n.string(.appHelpStudioJamSessionBody, language))
        case .compositionGuide:
            HelpContentView(title: L10n.string(.appHelpCompositionGuideTitle, language), body: L10n.string(.appHelpCompositionGuideBody, language))
        case .compositionComposition:
            HelpContentView(title: L10n.string(.appHelpCompositionTitle, language), body: L10n.string(.appHelpCompositionBody, language))
        case .compositionPieces:
            HelpContentView(title: L10n.string(.appHelpPiecesTitle, language), body: L10n.string(.appHelpPiecesBody, language)) {
                ScoreColorLegendView(language: language)
            }
        case .theorieAccords:
            HelpContentView(title: L10n.string(.appHelpAccordsTitle, language), body: L10n.string(.appHelpAccordsBody, language))
        case .theorieModes:
            HelpContentView(title: L10n.string(.appHelpModesTitle, language), body: L10n.string(.appHelpModesBody, language))
        case .theorieProgressions:
            HelpContentView(title: L10n.string(.appHelpProgressionsTitle, language), body: L10n.string(.appHelpProgressionsBody, language))
        case .theorieExploration:
            HelpContentView(title: L10n.string(.appHelpExplorationTitle, language), body: L10n.string(.appHelpExplorationBody, language))
        case .theorieTonnetz:
            HelpContentView(title: L10n.string(.appHelpTonnetzTitle, language), body: L10n.string(.appHelpTonnetzBody, language)) {
                TonnetzLegendView(language: language, axis: .horizontal)
            }
        case .theorieIntonations:
            HelpContentView(title: L10n.string(.appHelpIntonationsTitle, language), body: L10n.string(.appHelpIntonationsBody, language))
        case .theorieDissonances:
            HelpContentView(title: L10n.string(.appHelpDissonancesTitle, language), body: L10n.string(.appHelpDissonancesBody, language))
        case .settingsSons:
            HelpContentView(title: L10n.string(.appHelpSonsTitle, language), body: L10n.string(.appHelpSonsBody, language))
        case .settingsMidi:
            HelpContentView(title: L10n.string(.appHelpMidiTitle, language), body: L10n.string(.appHelpMidiBody, language))
        case .settingsMicrophone:
            HelpContentView(title: L10n.string(.appHelpMicrophoneTitle, language), body: L10n.string(.appHelpMicrophoneBody, language))
        case .settingsConsole:
            HelpContentView(title: L10n.string(.appHelpConsoleTitle, language), body: L10n.string(.appHelpConsoleBody, language))
        case .settingsCouleurs:
            HelpContentView(title: L10n.string(.appHelpCouleursTitle, language), body: L10n.string(.appHelpCouleursBody, language))
        case .settingsLLM:
            HelpContentView(title: L10n.string(.appHelpLLMTitle, language), body: L10n.string(.appHelpLLMBody, language))
        case .settingsLangue:
            HelpContentView(title: L10n.string(.appHelpLangueTitle, language), body: L10n.string(.appHelpLangueBody, language))
        case .settingsNotation:
            HelpContentView(title: L10n.string(.appHelpNotationTitle, language), body: L10n.string(.appHelpNotationBody, language))
        }
    }
}

extension View {
    /// Installs the `jamshackhelp://<HelpTopicID>` link interceptor wherever contextual help is
    /// actually shown (`ContextualHelpWindow` on macOS/visionOS, the sheet in `ContentView` on
    /// iOS/iPadOS) — these are two SEPARATE SwiftUI hierarchies (a `WindowGroup` vs a `.sheet`),
    /// so `.environment(\.openURL, ...)` must be installed independently in both; there is no
    /// single shared place to set it once. Not a real registered URL scheme — never sent to the
    /// system. Returns `.handled` for `jamshackhelp://` (else SwiftUI would additionally try, and
    /// silently fail, the system open path) and `.systemAction` for anything else, so a genuine
    /// `https://` link authored into help text (if that's ever added) keeps working normally.
    /// An unrecognized/malformed topic id (a typo in hand-authored markdown) just no-ops rather
    /// than crashing.
    func interceptHelpLinks(pinnedTopic: Binding<HelpTopicID?>) -> some View {
        environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "jamshackhelp", let topic = HelpTopicID(rawValue: url.host ?? "") else {
                return .systemAction
            }
            pinnedTopic.wrappedValue = topic
            return .handled
        })
    }
}

import SwiftUI
import AppCore
import JamShackUI
import Localization

/// "Lecture" sub-tab of the Guide tab — split horizontally per explicit user request: the
/// circle-of-fifths wheel on the left (originally 1/3 of the screen, widened 30% per a follow-
/// up request — see `wheelColumnWidth` below — reflecting the guide's active mode:
/// `bridge.state.wheel` already prioritizes the active guide step over any other source, see
/// `WebConsoleWheelState`'s own doc comment, so no guide-specific wheel state is needed), and
/// on the right (the remaining width), top to bottom: (2.a) a flattened textual description of the guide with
/// the active mode/chord highlighted (`GuideDescriptionView`), (2.b) the "indication de jeu"
/// row — notation/keyboards/tablature in 1:3:2 proportions (`GuidePlayIndicationRow`), and
/// (2.c) the full live keyboard reflecting the user's actual current playing
/// (`AutoCenteredKeyboardView`, same view every other "live" screen in this app uses).
/// Arrow-key navigation mirrors the web console's own guide keyboard shortcuts (up/down =
/// previous/next mode step, left/right = previous/next chord in the step's progression) —
/// active only while this sub-tab itself is focused, so it doesn't compete with text input
/// elsewhere in the app; a no-op whenever the guide isn't running
/// (`advanceGuideStep`/`advanceGuideChord` already guard on that themselves).
struct GuideLectureView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge
    /// Switches the parent `GuideView` back to its "Edition" sub-tab once the guide is
    /// stopped — called explicitly from the stop button's own action (NOT from `onDisappear`,
    /// which also fires on a plain manual tab switch and would fight that navigation instead
    /// of following it).
    let onGuideStopped: () -> Void

    @State private var actionError: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if let guide = bridge.state.guide, guide.isActive {
                activeLayout(guide: guide)
            } else {
                inactivePlaceholder
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            isFocused = true
            // Real bug fix: this screen never told `ImprovSession` it was the active one, so
            // the LUMI Keys' "suivre le guide" mode (`notifyActiveScreen`/`lumiSettings
            // .autoPropagateGuideMode`) never actually started from the SwiftUI app — the
            // CLI wires this at every screen switch (`JamShack`'s `runConsoleScreen`), the
            // app never did. Safe to call every time this sub-tab appears (idempotent).
            session.notifyActiveScreen(.guide)
        }
        .onDisappear { session.notifyActiveScreen(.other) }
        .onKeyPress(.upArrow) { session.advanceGuideStep(by: -1); return .handled }
        .onKeyPress(.downArrow) { session.advanceGuideStep(by: 1); return .handled }
        .onKeyPress(.leftArrow) { session.advanceGuideChord(by: -1); return .handled }
        .onKeyPress(.rightArrow) { session.advanceGuideChord(by: 1); return .handled }
    }

    @ViewBuilder
    private var inactivePlaceholder: some View {
        VStack(spacing: 12) {
            if let actionError {
                Text(actionError).foregroundStyle(.red).font(.caption)
            }
            if session.currentGuide == nil {
                Text(L10n.string(.appPlaceholderAucunGuideActif, session.currentLanguage)).foregroundStyle(.secondary)
                ActivateOrCreateBlock(
                    files: session.guideSequenceNames,
                    onActivate: { try session.useGuideSequence(named: $0) },
                    createButtonLabel: L10n.string(.appButtonCreerUnGuide, session.currentLanguage),
                    createAlertTitle: L10n.string(.appNouveauGuide, session.currentLanguage),
                    createFieldPlaceholder: L10n.string(.appFieldTitreGuide, session.currentLanguage),
                    onCreate: { session.newGuideSequence(title: $0) },
                    language: session.currentLanguage
                )
            } else {
                Button(L10n.string(.appButtonDemarrerLeGuide, session.currentLanguage)) {
                    do {
                        try session.startGuide()
                    } catch {
                        actionError = "\(error)"
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func activeLayout(guide: WebConsoleGuideState) -> some View {
        GeometryReader { proxy in
            // Wheel column widened 30% over the original 1/3 (= 13/30), per explicit user
            // request for better graphical balance; the right column shrinks to match (17/30)
            // rather than the two overlapping, so the split still exactly fills the screen.
            let wheelColumnWidth = proxy.size.width * 13 / 30
            let rightColumnWidth = proxy.size.width * 17 / 30
            HStack(spacing: 0) {
                CircleOfFifthsWheelView(
                    wheel: bridge.state.wheel, palette: bridge.state.palette,
                    paletteTextColors: bridge.state.paletteTextColors, tracks: bridge.state.tracks
                )
                .padding()
                .frame(width: wheelColumnWidth)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        controlBar
                        if let actionError {
                            Text(actionError).foregroundStyle(.red).font(.caption)
                        }
                        GuideDescriptionView(guide: guide, language: session.currentLanguage)
                        GuidePlayIndicationRow(
                            guide: guide, availableWidth: rightColumnWidth - 32,
                            palette: bridge.state.palette, paletteTextColors: bridge.state.paletteTextColors,
                            language: session.currentLanguage
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.string(.appLabelEnDirect, session.currentLanguage)).font(.subheadline).foregroundStyle(.secondary)
                            AutoCenteredKeyboardView(
                                heldPitches: guide.heldPitches, modeTones: guide.currentModeTones,
                                palette: bridge.state.palette, paletteTextColors: bridge.state.paletteTextColors
                            )
                        }
                    }
                    .padding()
                }
                .frame(width: rightColumnWidth)
            }
        }
    }

    private var controlBar: some View {
        HStack {
            Button(L10n.string(.appButtonArreterLeGuide, session.currentLanguage), role: .destructive) {
                session.stopGuide()
                onGuideStopped()
            }
            Spacer()
            Button(L10n.string(.appButtonPrecedent, session.currentLanguage)) { session.advanceGuideStep(by: -1) }
            Button(L10n.string(.appButtonSuivant, session.currentLanguage)) { session.advanceGuideStep(by: 1) }
        }
    }
}

#Preview {
    let session = ImprovSession()
    return GuideLectureView(session: session, bridge: SessionUIBridge(session: session), onGuideStopped: {})
}

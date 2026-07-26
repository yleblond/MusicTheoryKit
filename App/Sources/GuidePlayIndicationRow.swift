import SwiftUI
import AppCore
import MusicTheoryKit
import PieceModel
import JamShackUI
import Localization

/// 2.b of the Guide "Lecture" screen: the "indication de jeu" row, left to right — notation
/// (1/6 of the row's width), the mode+chord reference keyboards stacked (3/6), and the guitar
/// tablature (2/6) — proportions per explicit user request. `availableWidth` is passed down
/// from the screen's own outer `GeometryReader` (`GuideLectureView`) rather than measured by a
/// second, nested one here: a `GeometryReader` always reports the FULL proposed size of its
/// parent context (here, effectively unbounded height inside a `ScrollView`), not this row's
/// own natural content height, so nesting one to also solve for width would force picking an
/// arbitrary fixed height and risk clipping the staff notation (whose natural height already
/// exceeds a plausible guess) — same tension the web console's own `renderStaffSVG` doc
/// comment describes hitting with pure CSS. Only rendered once a chord is actually selected
/// (`guide.currentChordIndex != nil`); before that, only the mode keyboard shows (full width),
/// matching the web console's own `renderGuide` gating.
struct GuidePlayIndicationRow: View {
    let guide: WebConsoleGuideState
    let availableWidth: CGFloat
    let palette: [String]
    let paletteTextColors: [String]
    let language: AppLanguage

    private static let keyboardMinMidi = 60
    private static let keyboardMaxMidi = 83 // 2 octaves, same range the web console's own Guide keyboards use
    /// -30% off `PitchKeyboardView`'s own default 144, per explicit user request — these two
    /// are static reference keyboards, not the live "En direct" one, so they can afford to be
    /// noticeably smaller.
    private static let keyboardHeight: CGFloat = 144 * 0.7
    /// -10% off `ChordStaffView`'s own default (unscaled) height, per explicit user request.
    private static let staffHeightScale: CGFloat = 0.9

    private var hasChord: Bool { guide.currentChordIndex != nil }

    var body: some View {
        if hasChord {
            HStack(alignment: .top, spacing: 8) {
                staffColumn.frame(width: availableWidth * 1 / 6)
                keyboardsColumn.frame(width: availableWidth * 3 / 6)
                tabColumn.frame(width: availableWidth * 2 / 6)
            }
        } else {
            keyboardsColumn
        }
    }

    @ViewBuilder
    private var staffColumn: some View {
        VStack(spacing: 4) {
            Text(L10n.string(.headingPartitionGuideWeb, language)).font(.caption).foregroundStyle(.secondary)
            ChordStaffView(
                events: [ChordStaffView.chordEvent(root: guide.currentChordRoot ?? 0, tones: guide.currentChordTones)],
                heightScale: Self.staffHeightScale
            )
        }
    }

    @ViewBuilder
    private var keyboardsColumn: some View {
        VStack(spacing: 8) {
            Text(L10n.string(.appHeadingClavierDuMode, language)).font(.caption).foregroundStyle(.secondary)
            PitchKeyboardView(
                minMidi: Self.keyboardMinMidi, maxMidi: Self.keyboardMaxMidi,
                modeTones: guide.currentModeTones, showModeColoring: true,
                palette: palette, paletteTextColors: paletteTextColors,
                height: Self.keyboardHeight
            )
            if hasChord {
                Text(L10n.string(.appHeadingClavierAccord, language)).font(.caption).foregroundStyle(.secondary)
                PitchKeyboardView(
                    minMidi: Self.keyboardMinMidi, maxMidi: Self.keyboardMaxMidi,
                    chordRoot: guide.currentChordRoot, chordTones: guide.currentChordTones, alwaysShowChord: true,
                    palette: palette, paletteTextColors: paletteTextColors,
                    height: Self.keyboardHeight
                )
            }
        }
    }

    @ViewBuilder
    private var tabColumn: some View {
        VStack(spacing: 4) {
            Text(L10n.string(.headingTablatureGuideWeb, language)).font(.caption).foregroundStyle(.secondary)
            GuitarChordDiagramView(
                webDiagram: guide.currentChordGuitarDiagram,
                fallbackLabel: guide.currentChordProgression[safe: guide.currentChordIndex ?? -1]?.label ?? ""
            )
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    // `WebConsoleGuideState` has no public initializer (see `WebConsoleState.swift`'s own
    // doc comment) — building one for a preview goes through a real session's real API.
    let session = ImprovSession()
    session.newGuideSequence(title: L10n.string(.appDefaultGuideTitle, session.currentLanguage))
    try? session.addGuideStep(ModeReference(tonic: 0, scaleID: ScaleLibrary.all[0].id), chordProgression: session.chordProgressionTemplates.first)
    try? session.startGuide()
    session.advanceGuideChord(by: 1)
    let guide = session.buildWebConsoleState().guide!
    return GuidePlayIndicationRow(
        guide: guide, availableWidth: 600,
        palette: PitchKeyboardView.defaultPalette, paletteTextColors: PitchKeyboardView.defaultPaletteTextColors,
        language: session.currentLanguage
    )
    .padding()
}

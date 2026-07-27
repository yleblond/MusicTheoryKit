import SwiftUI
import AppCore
import Localization

/// Equivalent of the console's/CLI's "Run" view: the circle-of-fifths wheel on the left
/// (always present, same as `SessionUIBridge.state.wheel` itself — never gated behind an
/// active guide), and every currently-listening track on the right, each showing its held
/// notes on a `PitchKeyboardView` plus its recognized chord/mode labels — driven live by a
/// `SessionUIBridge`. The first screen that proves the full chain end to end (bridge
/// polling -> per-track adapter -> `PitchKeyboardView`); the wheel used to be its own tab,
/// merged in here so both are visible together without switching tabs. Every track's keyboard
/// here is read-only display — actual computer-keyboard input now goes exclusively through the
/// persistent bottom bar (`ComputerKeyboardInputBar`, see `ContentView`), not through tapping a
/// track's own mini keyboard (that capability existed before the bar did and was removed once
/// it made the bar redundant/confusing to have two active input surfaces at once).
public struct RunScreen: View {
    public let session: ImprovSession
    public let bridge: SessionUIBridge

    @State private var recordingError: String?

    public init(session: ImprovSession, bridge: SessionUIBridge) {
        self.session = session
        self.bridge = bridge
    }

    public var body: some View {
        HStack(spacing: 0) {
            CircleOfFifthsWheelView(
                wheel: bridge.state.wheel,
                palette: bridge.state.palette,
                paletteTextColors: bridge.state.paletteTextColors,
                tracks: bridge.state.tracks
            )
                .padding()
                .frame(width: 525) // +75% over the original 300 — explicit user request.
            Divider()
            VStack(spacing: 0) {
                recordingBar
                List(bridge.state.tracks, id: \.id) { track in
                    TrackRunRow(
                        track: track,
                        palette: bridge.state.palette,
                        paletteTextColors: bridge.state.paletteTextColors
                    )
                }
                #if os(macOS)
                .listStyle(.inset)
                #endif
            }
        }
    }

    /// Records every currently-listening track (`startRecording`'s own default when `tracks` is
    /// empty) — merged here from what used to be a separate "Record" sub-tab of a standalone
    /// "Enregistrement" tab (2026-07-26): no manual track-selection step, since a scene's own
    /// attached/listening instruments already say what should be captured. Playback/loading of
    /// the result lives in the Studio tab's own sibling sub-tabs.
    @ViewBuilder
    private var recordingBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let recordingError {
                Text(recordingError).font(.caption).foregroundStyle(.red)
            }
            if session.isRecording {
                Button(role: .destructive) {
                    do {
                        _ = try session.stopRecording()
                    } catch {
                        recordingError = "\(error)"
                    }
                } label: {
                    Label(L10n.string(.appButtonArreterEnregistrement, session.currentLanguage), systemImage: "stop.circle.fill")
                }
            } else {
                Button {
                    recordingError = nil
                    do {
                        try session.startRecording(title: L10n.string(.catEnregistrement, session.currentLanguage))
                    } catch {
                        recordingError = "\(error)"
                    }
                } label: {
                    Label(L10n.string(.appButtonDemarrerEnregistrement, session.currentLanguage), systemImage: "record.circle")
                }
            }
        }
        .padding([.horizontal, .top])
    }
}

private struct TrackRunRow: View {
    let track: WebConsoleTrackState
    let palette: [String]
    let paletteTextColors: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(track.label).font(.headline)
                if let owner = track.owner {
                    Text("(\(owner))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let chordLabel = track.chordLabel {
                    Text(chordLabel).font(.headline).foregroundStyle(Color.accentColor)
                }
            }
            // Always rendered (never conditionally inserted/removed) even when there's nothing
            // to show — an `if let ... { Text(...) }` here made these two lines appear/disappear
            // as recognition came and went, which shoved the keyboard below down/up on every
            // detection change ("jittering"), confirmed as the actual cause rather than the
            // keyboard itself (`AutoCenteredKeyboardView`/`PitchKeyboardView` are already a fixed
            // height, independent of the detected chord/mode).
            Text(track.modesLabel ?? " ").font(.caption).foregroundStyle(.secondary)
            Text(track.recognitionMode ?? " ").font(.caption2).foregroundStyle(.secondary)
            AutoCenteredKeyboardView(
                heldPitches: track.heldPitches,
                chordRoot: track.chordRoot,
                chordTones: track.chordTones,
                modeTones: track.modeTones,
                palette: palette,
                paletteTextColors: paletteTextColors,
                keyboardHeight: 144 * 0.7 // -30%, explicit user request — same ratio already
                                          // used by `GuidePlayIndicationRow`'s reference keyboards.
            )
        }
        .padding(.vertical, 6)
    }
}

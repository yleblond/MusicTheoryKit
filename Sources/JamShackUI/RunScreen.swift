import SwiftUI
import AppCore

/// Equivalent of the console's/CLI's "Run" view: the circle-of-fifths wheel on the left
/// (always present, same as `SessionUIBridge.state.wheel` itself — never gated behind an
/// active guide), and every currently-listening track on the right, each showing its held
/// notes on a `PitchKeyboardView` plus its recognized chord/mode labels — driven live by a
/// `SessionUIBridge`. The first screen that proves the full chain end to end (bridge
/// polling -> per-track adapter -> `PitchKeyboardView`); the wheel used to be its own tab,
/// merged in here so both are visible together without switching tabs.
public struct RunScreen: View {
    public let bridge: SessionUIBridge
    /// The `WebConsoleTrackState.id` (e.g. `"clavier"` for `.computerKeyboard`) allowed to be
    /// played by tapping/clicking its own keyboard — the "clavier virtuel" counterpart to the
    /// web console's clickable virtual-keyboard page. Every other track's keyboard stays
    /// read-only (tapping a MIDI-sourced track's display shouldn't inject a note into it).
    public let interactiveTrackID: String?
    public let onNoteOn: ((Int) -> Void)?
    public let onNoteOff: ((Int) -> Void)?

    public init(
        bridge: SessionUIBridge,
        interactiveTrackID: String? = nil,
        onNoteOn: ((Int) -> Void)? = nil,
        onNoteOff: ((Int) -> Void)? = nil
    ) {
        self.bridge = bridge
        self.interactiveTrackID = interactiveTrackID
        self.onNoteOn = onNoteOn
        self.onNoteOff = onNoteOff
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
                .frame(width: 300)
            Divider()
            List(bridge.state.tracks, id: \.id) { track in
                let isInteractive = track.id == interactiveTrackID
                TrackRunRow(
                    track: track,
                    onNoteOn: isInteractive ? onNoteOn : nil,
                    onNoteOff: isInteractive ? onNoteOff : nil
                )
            }
            #if os(macOS)
            .listStyle(.inset)
            #endif
        }
    }
}

private struct TrackRunRow: View {
    let track: WebConsoleTrackState
    let onNoteOn: ((Int) -> Void)?
    let onNoteOff: ((Int) -> Void)?

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
            if let modesLabel = track.modesLabel {
                Text(modesLabel).font(.caption).foregroundStyle(.secondary)
            }
            if let recognitionMode = track.recognitionMode {
                Text(recognitionMode).font(.caption2).foregroundStyle(.secondary)
            }
            // C2...C7 (5 octaves) rather than the tighter 2-octave default: a real MIDI
            // controller's playing range varies a lot (a 25-key controller centered on C3,
            // a 61-key spanning C2-C6...), and a held note outside the displayed range
            // simply never lights up even though it's correctly recognized (the recognized
            // chord/mode labels above are unaffected either way, since those don't depend
            // on this view's range). Static for now — the web console's Observer tab
            // auto-centers its window on whatever's actually held; doing the same here
            // would be the next real improvement over a fixed range.
            PitchKeyboardView(
                minMidi: 36,
                maxMidi: 96,
                heldPitches: Set(track.heldPitches),
                chordRoot: track.chordRoot,
                chordTones: track.chordTones,
                modeTones: track.modeTones,
                onNoteOn: onNoteOn,
                onNoteOff: onNoteOff
            )
        }
        .padding(.vertical, 6)
    }
}
